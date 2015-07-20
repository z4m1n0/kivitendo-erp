namespace('kivi.Sepa', function(ns) {
  this.paymentTypeChanged = function() {
    var type_id = $(this).attr('id');
    var id      = type_id.match(/\d*$/);

    // console.log("found id " + id);

    if ( $(this).val() == "without_skonto" )
      $('#' + id).val( $('#invoice_open_amount_' + id).val() );

    else if ( $(this).val() == "difference_as_skonto" )
      $('#' + id).val( $('#invoice_open_amount_' + id).val() );

    else if ( $(this).val() == "with_skonto_pt" )
      $('#' + id).val( $('#amount_less_skonto_' + id).val() );
  };

  this.initBankTransferAdd = function(vc) {
    $("#select_all").checkall('INPUT[name="bank_transfers[].selected"]');
    $(".type_target").change(kivi.Sepa.paymentTypeChanged);
  };
});
