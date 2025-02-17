use Modern::Perl;
use Koha::Installer::Output qw(say_warning say_success say_info);

return {
    bug_number  => "39140",
    description => "Add a feature to define hold pickup shelves",
    up          => sub {
        my ($args) = @_;
        my ( $dbh, $out ) = @$args{qw(dbh out)};

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable,value,options,explanation,type) VALUES
            ('HoldPickupShelves','0','0=No|1=Yes','Define hold pickup shelves', 'YesNo')
        });

        say_success( $out, "Added new system preference 'HoldPickupShelves'");

        $dbh->do(q{
            INSERT IGNORE INTO systempreferences (variable,value,options,explanation,type) VALUES
            ('HoldPickupShelvesBiblioLevelItemTypeParameter','','','URL for biblio level item type API fetch', 'FreeText')
        });

        say_success( $out, "Added new system preference 'HoldPickupShelvesBiblioLevelItemTypeParameter'");

        unless ( TableExists('hold_pickup_shelves') ) {
            $dbh->do(q{
                CREATE TABLE `hold_pickup_shelves` (
                `hold_pickup_shelf_id` int(11) NOT NULL AUTO_INCREMENT,
                `library_id` varchar(10) NOT NULL,
                `patron_id` int(11) DEFAULT NULL,
                `shelf_name` varchar(100) NOT NULL,
                `max_items` int(11) NOT NULL,
                `overflow_shelf` tinyint(1) DEFAULT 0,
                `locked` tinyint(1) DEFAULT 0,
                `locked_date` datetime DEFAULT NULL,
                `biblio_itemtype` varchar(10) DEFAULT NULL,
                `patron_category_id` varchar(10) DEFAULT NULL,
                `weekday` enum('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') DEFAULT NULL,
                `priority` int(11) DEFAULT 0,
                PRIMARY KEY (`hold_pickup_shelf_id`),
                UNIQUE KEY `hold_pickup_shelves_uniq_idx` (`library_id`,`shelf_name`,`biblio_itemtype`,`patron_category_id`,`weekday`),
                KEY `patron_id` (`patron_id`),
                KEY `patron_category_id` (`patron_category_id`),
                CONSTRAINT `hold_pickup_shelves_ibfk_library` FOREIGN KEY (`library_id`) REFERENCES `branches` (`branchcode`) ON DELETE CASCADE,
                CONSTRAINT `hold_pickup_shelves_ibfk_patron` FOREIGN KEY (`patron_id`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE SET NULL,
                CONSTRAINT `hold_pickup_shelves_ibfk_category` FOREIGN KEY (`patron_category_id`) REFERENCES `categories` (`categorycode`) ON DELETE CASCADE
                ) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
            });

            say_success( $out, "Added new table 'hold_pickup_shelves'" );
        }

        if ( !column_exists( 'reserves', 'hold_pickup_shelf_id' ) ) {
            $dbh->do(q{
                ALTER TABLE reserves
                ADD COLUMN hold_pickup_shelf_id INT,
                ADD FOREIGN KEY (hold_pickup_shelf_id) REFERENCES hold_pickup_shelves(hold_pickup_shelf_id)
            });

            say_success( $out, "Added column 'reserves.hold_pickup_shelf_id'" );
        }
        if ( !column_exists( 'old_reserves', 'hold_pickup_shelf_id' ) ) {
            $dbh->do(q{
                ALTER TABLE old_reserves
                ADD COLUMN hold_pickup_shelf_id INT,
                ADD FOREIGN KEY (hold_pickup_shelf_id) REFERENCES hold_pickup_shelves(hold_pickup_shelf_id) ON DELETE SET NULL
            });

            say_success( $out, "Added column 'old_reserves.hold_pickup_shelf_id'" );
        }

    },
};
