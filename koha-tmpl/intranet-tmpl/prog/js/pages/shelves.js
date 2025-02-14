
$(document).ready(function () {

    $(".moretogglelist").click(function (e) {
        e.preventDefault();
        $(this).siblings(".collapsible-callnumber").toggle();
        $(this).siblings(".moretogglelist").toggle();
        $(this).toggle();
    });
});
