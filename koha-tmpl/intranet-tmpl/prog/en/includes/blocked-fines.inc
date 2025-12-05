[% USE Price %]
[% USE Categories %]
[% IF total and total > 0 %]
    <li>
        <span class="circ-hlt">Charges:</span>
        <span>Patron has blocking charges of [% NoIssuesCharge | $Price with_symbol => 1 %].</span>
        <span>Total (incl. non-blocking): [% total | $Price with_symbol => 1 %].</span>
        [% IF !Koha.Preference('AllowFineOverride') && NoIssuesCharge.limit && NoIssuesCharge.overlimit %]
            <span class="circ-hlt">Checkouts are BLOCKED because fine balance is OVER THE LIMIT.</span>
        [% END %]
        [% IF CAN_user_updatecharges_remaining_permissions %]
            <a href="/cgi-bin/koha/members/pay.pl?borrowernumber=[% patron.borrowernumber | uri %]" class="btn btn-default btn-xs">Make payment</a>
            <a href="/cgi-bin/koha/members/paycollect.pl?borrowernumber=[% patron.borrowernumber | uri %]" class="btn btn-default btn-xs">Pay all charges</a>
        [% END %]
    </li>
[% END %]
