# vim:set tabstop=4 shiftwidth=4 noexpandtab:

use strict;
use ExtUtils::MakeMaker;
use Getopt::Long;
use Config;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $options;
my $testno=1;
my %MakeParams = InitMakeParams();

WriteMakefile(%MakeParams);


sub MY::postamble {	
	"
LibIDN.pm: _LibIDN.pm _test.pl
	perl Makefile.PL $options

test.pl: _test.pl
	perl Makefile.PL $options
"
}

sub InitMakeParams
{
	my %Params =
	(
		'NAME'			=> 'Net::LibIDN',
		'VERSION_FROM'	=> 'LibIDN.pm', # finds $VERSION
		'PREREQ_PM'		=> {}, # e.g., Module::Name => 1.1
		($] >= 5.005 ?	## Add these new keywords supported since 5.005
		(ABSTRACT_FROM	=> 'LibIDN.pm', # retrieve abstract from module
		AUTHOR			=> 'Thomas Jacob <jacob@internet24.de>') : ()),
		PM				=> { 'LibIDN.pm' => '$(INST_LIB)/Net/LibIDN.pm' },
		clean			=> { FILES => "test.pl LibIDN.pm" }
	);
	my ($libdir, $incdir, $libdir2, $incdir2, $disable_tld, $disable_libidn2,
		$force_libidn, $force_libidn2, $force_tld);

	$options=join(' ', @ARGV);

	GetOptions
	(
		"with-libidn=s" => \$libdir,
		"with-libidn-inc=s" => \$incdir,
		"with-libidn2=s" => \$libdir2,
		"with-libidn2-inc=s" => \$incdir2,
		"disable-tld" => \$disable_tld,
		"disable-libidn2" => \$disable_libidn2,
		"force-libidn" => \$force_libidn,
		"force-libidn2" => \$force_libidn2,
		"force-tld" => \$force_tld
	);


	$Params{INC} = '';
	$Params{LIBS} = '';
	$Params{DEFINE} = '';

	$Params{LIBS} .= " -L$libdir" if $libdir;
	$Params{LIBS} .= ' -lidn';
	$Params{INC} .= "-I$incdir" if $incdir;

	$Params{LIBS} .= "-L$libdir2" if $libdir2;
	$Params{INC} = "-I$incdir2" if $incdir2;

	my $libidn;
	if ($force_libidn)
	{
		$libidn = $force_tld?2:1;
		print "Forced GNU LibIDN, ";
	}
	else
	{
		my $libidn = CheckLibidn($Params{INC}, $Params{LIBS});

		unless($libidn)
		{
			print "This module requires GNU Libidn, which could not be found.\n" unless $libidn;
			exit 0;
		}

		print "Found GNU LibIDN, ";
	}
	print $libidn == 1? "without": "with";
	print " TLD checking support\n";

	if ($libidn == 2 && $disable_tld)
	{
		print "TLD checking support disabled at user request\n";
	}

	$disable_tld = 1 if ($libidn<2);

	$Params{DEFINE} .= ' -DHAVE_TLD' unless $disable_tld;

	my $libidn2;

	if ($force_libidn2)
	{
		$libidn2 = 1;
		print "Forced GNU LibIDN2\n";
	}
	else
	{
		$libidn2 = CheckLibidn2($Params{INC}, $Params{LIBS}. ' -lidn2');
		print "Found GNU LibIDN2\n" if $libidn2;
	}
	
	if ($libidn2)
	{
		$Params{LIBS} .= ' -lidn2';
		$Params{DEFINE} .= ' -DHAVE_LIBIDN2';
	}

	Filter("_LibIDN.pm", "LibIDN.pm", {TLD => !$disable_tld, IDN2 => $libidn2});
	Filter("_test.pl", "test.pl", {TLD => !$disable_tld, IDN2 => $libidn2});

	return(%Params);
}

sub Filter
{
	my ($in, $out, $tags) = @_;
	local *IN, *OUT;

	open(IN, "<$in") || die "Can't open file $in\n";
	open(OUT, ">$out") || die "Can't write file $out\n";

	my (%inside, %else);

OUTER:
	while (my $line = <IN>)
	{
		while (my ($tag, $include) = each %$tags)
		{
			if ($line =~ m/^#IF_$tag/)
			{
				$inside{$tag} = 1;
				next OUTER;
			}
			if ($line =~ m/^#ELSE_$tag/)
			{
				$else{$tag} = 1;
				next OUTER;
			}
			if ($line =~ m/^#ENDIF_$tag/)
			{
				$inside{$tag} = 0;
				$else{$tag} = 0;
				next OUTER;
			}
		}

		my $output = 1;
		while (my ($tag, $include) = each %$tags)
		{
			if ($inside{$tag})
			{
				if ($include)
				{
					$output = 0 if $else{$tag}
				}
				elsif (!$else{$tag})
				{
					$output = 0;
				}
			}
		}

		print OUT $line if $output;
	}
}

sub CheckCCode
{
	my $code = shift;
	my $cflags = shift;
	my $ldflags = shift;
	my $output = shift;
	my $test = '__test'.$testno++;
	local * FILE;

	if (open(FILE, ">$test.c"))
	{
		print FILE $code;
		close(FILE);
	}
	else
	{
		return 0;
	}

	foreach my $cc ($Config{cc})
	{
		unlink($test);
		print "$cc $cflags -o $test $test.c $ldflags\n";
		system "$cc $cflags -o $test $test.c $ldflags";
		next if ($? >> 8);

		if (open(FILE, "./$test|"))
		{
			my $match;
			while(<FILE>)
			{
				$match = 1 if $_ eq $output;
				last;
			}
			close(FILE);
			next unless $match;
		}
		else
		{
			next;
		}
		unlink($test);
		unlink("$test.c");
		return 1;
	}
	return 0;
}

sub CheckLibidn
{
	my $cflags = shift;
	my $ldflags = shift;
	my $result;
	my $final;
	local * FILE;

	my $test1 = <<EOT;
#include <idna.h>
#include <stdio.h>
int main(void)
{
	char * output;
	int res;
	
	res = idna_to_ascii_8z("libidn", &output, 0);
	printf("%d-%s", res, output);

	return 0;
}
EOT
	return $result unless CheckCCode($test1, $cflags, $ldflags, "0-libidn");

	$result = 1;

	my $test2 = <<EOT;
#include <tld.h>
#include <stdio.h>
int main(void)
{
	char * output;
	int res;

	res =tld_get_z ("libidn.idn", &output);	
	printf("%d-%s", res, output);
	
	return 0;
}
EOT

	return $result unless CheckCCode($test2, $cflags, $ldflags, "0-idn");
	
	return 2;
}

sub CheckLibidn2
{
	my $cflags = shift;
	my $ldflags = shift;
	my $result;
	my $final;
	local * FILE;

	my $test1 = <<EOT;
#include <idn2.h>
#include <stdio.h>
int main(void)
{
	const char * output = idn2_check_version ("0.3");
	
	if (output == NULL)
	{
		printf("%s", output);
		return 0;
	}
	else
		return 1;
}
EOT
	return $result unless CheckCCode($test1, $cflags, $ldflags, "0.3", 1);

	$result = 1;
}

