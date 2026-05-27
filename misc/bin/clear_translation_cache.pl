#!/usr/bin/perl

# Clear translation cache across all Plack workers using memcached
# Run this after:
#   - Updating .po/.mo translation files
#   - Changing language configuration
#   - Any translation-related changes
#
# This increments a version counter in memcached. All workers will
# detect the version change on their next request and reinitialize.

use Modern::Perl;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/../..";

use Koha::Caches;

my $verbose = 0;
GetOptions(
    'verbose|v' => \$verbose,
) or die "Usage: $0 [-v|--verbose]\n";

print "=" x 70 . "\n";
print "Koha Translation Cache Invalidation\n";
print "=" x 70 . "\n\n";

my $cache = Koha::Caches->get_instance();

# Get current version
my $old_version = $cache->get_from_cache('i18n:translation_version') || 0;

# Increment version
my $new_version = $old_version + 1;

# Store new version in memcached (expires after 30 days as safety)
$cache->set_in_cache('i18n:translation_version', $new_version, { expiry => 30 * 24 * 60 * 60 });

print "Translation version updated:\n";
print "  Previous version: $old_version\n";
print "  New version:      $new_version\n\n";

if ($verbose) {
    print "What happens next:\n";
    print "  1. All Plack workers will check memcached on next request\n";
    print "  2. Workers detect version changed ($old_version → $new_version)\n";
    print "  3. Each worker clears its local i18n and language cache\n";
    print "  4. Fresh language detection and translation loading happens\n";
    print "  5. Zero downtime - no restart needed!\n\n";
    
    print "Cache details:\n";
    print "  Storage:        memcached (shared across all workers)\n";
    print "  Key:            i18n:translation_version\n";
    print "  Expiry:         30 days (auto-renewed on updates)\n";
    print "  Workers:        Will sync within seconds\n\n";
}

print "✓ Translation cache invalidated successfully\n";
print "\n";

if (!$verbose) {
    print "Run with --verbose or -v for more details\n";
}

print "=" x 70 . "\n";

exit 0;
