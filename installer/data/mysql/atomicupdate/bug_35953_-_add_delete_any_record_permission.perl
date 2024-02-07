$DBversion = 'XXX';
if( CheckVersion( $DBversion ) ) {
    $dbh->do(q{INSERT IGNORE INTO permissions (module_bit, code, description) VALUES (9, 'delete_any_record', 'Delete any existing record')});

    NewVersion( $DBversion, undef, "Add delete_any_record user permission" );
}
