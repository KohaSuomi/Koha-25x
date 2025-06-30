package C4::KohaSuomi::hdiacritic;
use Text::Unaccent;
use Modern::Perl;
use utf8;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(hdiacritic);
use Text::Unaccent;

sub convert {
    my $char;
    my $oldchar;
    my $string;

    foreach ( split( //, $_[0] ) ) {
        $char    = $_;
        $oldchar = $char;
        unless ( $char =~ /[A-Za-z0-9ÅåÄäÖöÉéÜüÁá]/ ) {
            $char = 'Z'  if $char eq 'Ʒ';
            $char = 'z'  if $char eq 'ʒ';
            $char = 'B'  if $char eq 'ß';
            $char = '\'' if $char eq 'ʻ';
            $char = 'e'  if $char eq '€';
            # Ensure $char is valid before calling unac_string
            if ( defined $char && length($char) > 0 ) {
                $char = unac_string( 'utf-8', $char ) if "$oldchar" eq "$char";
            }
        }
        $string .= $char;
    }

    return $string;
}
1;