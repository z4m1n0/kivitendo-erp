namespace('kivi.Sepa', function(ns) {
  ns.paymentTypeChanged = function() {
    var type_id = $(this).attr('id');
    var id      = type_id.match(/\d*$/);

    // console.log("found id " + id);

    if ( $(this).val() == "without_skonto" )
      $('#' + id).val( $('#invoice_open_amount_' + id).val() );

    else if ( $(this).val() == "difference_as_skonto" )
      $('#' + id).val( $('#invoice_open_amount_' + id).val() );

    else if ( $(this).val() == "with_skonto_pt" )
      $('#' + id).val( $('#amount_less_skonto_' + id).val() );
    kivi.Sepa.updateSumAmount();
  };

  ns.verifyBankAccountSelected = function() {
    if ($('#bank_account').val())
      return true;

    alert(kivi.t8('You have to select a bank account.'));
    return false;
  };

  ns.selectRow = function(elem) {
    if ( elem.target.localName != 'td' )
	return true;
    if ($(this).find('INPUT[name="bank_transfers[].selected"]').prop('checked'))
      $(this).find('INPUT[name="bank_transfers[].selected"]').prop('checked', false);
    else
      $(this).find('INPUT[name="bank_transfers[].selected"]').prop('checked', true);
    kivi.Sepa.updateSumAmount();
    return false;
  };

  ns.updateSumAmount = function() {
    var sum_amount=0;
    $('INPUT[name="bank_transfers[].selected"]:checked').each(function(idx,elem)
       {
	   var $trans = $(elem).closest('tr').find('INPUT[name="bank_transfers[].amount"]');
           sum_amount += kivi.parse_amount($trans.val());
       });
    $('#sepa_sum_amount').text(kivi.format_amount(sum_amount,2));
    return false;
  };

  ns.initBankTransferAdd = function(vc) {
    $("#select_all").checkall('INPUT[name="bank_transfers[].selected"]');
    $("#select_all").change(kivi.Sepa.updateSumAmount);
    $('INPUT[name="bank_transfers[].selected"]').change(kivi.Sepa.updateSumAmount);
    $('INPUT[name="bank_transfers[].amount"]').change(kivi.Sepa.updateSumAmount);
    $(".type_target").change(kivi.Sepa.paymentTypeChanged);
    $('.invoice_row').click(kivi.Sepa.selectRow);
    $('[type=submit]').click(kivi.Sepa.verifyBankAccountSelected);
  };
});
