# @tag: currencies
# @description: Erstellt neue Tabelle currencies. Währungen können dann einfacher eingegeben und unkritisch geändert werden.
# @depends: release_3_0_0 rm_whitespaces
# @charset: utf-8

use utf8;
use strict;

die("This script cannot be run from the command line.") unless ($main::form);

sub mydberror {
  my ($msg) = @_;
  die($dbup_locale->text("Database update error:") . "<br>$msg<br>" . $DBI::errstr);
}

sub do_query {
  my ($query, $may_fail) = @_;

  if (!$dbh->do($query)) {
    mydberror($query) unless ($may_fail);
    $dbh->rollback();
    $dbh->begin_work();
  }
}


sub do_update {
  #Check wheather default currency exists
  my $query = qq|SELECT curr FROM defaults|;
  my ($currencies) = $dbh->selectrow_array($query);

  if (length($currencies) == 0 and length($main::form->{defaultcurrency}) == 0){
    print_no_default_currency();
    return 2;
  } else {
    if (length($main::form->{defaultcurrency}) == 0){
      $main::form->{defaultcurrency} = (split m/:/, $currencies)[0];
    }
  }
  my @currency_array = grep {$_ ne '' } split m/:/, $currencies;

  $query = qq|SELECT DISTINCT curr FROM ar
              UNION
              SELECT DISTINCT curr FROM ap
              UNION
              SELECT DISTINCT curr FROM oe
              UNION
              SELECT DISTINCT curr FROM customer
              UNION
              SELECT DISTINCT curr FROM delivery_orders
              UNION
              SELECT DISTINCT curr FROM exchangerate
              UNION
              SELECT DISTINCT curr FROM vendor|;

  my $sth = $dbh->prepare($query);
  $sth->execute || $self->dberror($query);

  $main::form->{ORPHANED_CURRENCIES} = [];
  my $is_orphaned;
  my $rowcount = 0;
  while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
    next unless length($ref->{curr}) > 0;
    $is_orphaned = 1;
    foreach my $key (split(/:/, $currencies)) {
      if ($ref->{curr} eq $key) {
        $is_orphaned = 0;
        last;
      }
    }
    if ($is_orphaned) {
     push @{ $main::form->{ORPHANED_CURRENCIES} }, $ref;
     $main::form->{ORPHANED_CURRENCIES}[$rowcount]->{name} = "curr_$rowcount";
     $rowcount++;
    }
  }

  $sth->finish;

  if (scalar @{ $main::form->{ORPHANED_CURRENCIES} } > 0 and not ($main::form->{continue_options})) {
    print_orphaned_currencies();
    return 2;
  }

  if ($main::form->{continue_options} eq 'break_up') {
    return 0;
  }

  if ($main::form->{continue_options} eq 'insert') {
    for my $i (0..($rowcount-1)){
      push @currency_array, $form->{"curr_$i"};
    }
    create_and_fill_table(@currency_array);
    return 1;
  }

  my $still_orphaned;
  if ($main::form->{continue_options} eq 'replace') {
    for my $i (0..($rowcount - 1)){
      $still_orphaned = 1;
      for my $item (@currency_array){
        if ($main::form->{"curr_$i"} eq $item){
          $still_orphaned = 0;
          $query = qq|DELETE FROM exchangerate WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE ap SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE ar SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE oe SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE customer SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE delivery_orders SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          $query = qq|UPDATE vendor SET curr = '| . $main::form->{"curr_$i"} . qq|' WHERE curr = '| . $main::form->{"old_curr_$i"} . qq|'|;
          do_query($query);
          last;
        }
      }
      if ($still_orphaned){
        $main::form->{continue_options} = '';
        return do_update();
      }
    }
    create_and_fill_table(@currency_array);
    return 1;
  }

  #No orphaned currencies, so create table:
  create_and_fill_table(@currency_array);
  return 1;
}; # end do_update

sub create_and_fill_table {
  #Create an fill table currencies:
  my $query = qq|CREATE TABLE currencies (id INTEGER DEFAULT nextval(('id'::text)::regclass) UNIQUE NOT NULL, curr TEXT PRIMARY KEY)|;
  do_query($query);
  foreach my $item ( @_ ) {
    $query = qq|INSERT INTO currencies (curr) VALUES ('| . $item . qq|')|;
    do_query($query);
  }

  #Set default currency if no currency was chosen:
  $query = qq|UPDATE ap SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|UPDATE ar SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|UPDATE oe SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|UPDATE customer SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|UPDATE delivery_orders SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|UPDATE vendor SET curr = '| . $main::form->{"defaultcurrency"} . qq|' WHERE curr IS NULL or curr='';|;
  $query .= qq|DELETE FROM exchangerate WHERE curr IS NULL or curr='';|;
  do_query($query);

  #Check wheather defaultcurrency is already in table currencies:
  $query = qq|SELECT curr FROM currencies WHERE curr = '| . $main::form->{defaultcurrency} . qq|'|;
  my ($insert_default) = $dbh->selectrow_array($query);

  if (!$insert_default) {
    $query = qq|INSERT INTO currencies (curr) VALUES ('| . $main::form->{defaultcurrency} . qq|')|;
    do_query($query);
  }

  #Create a new columns currency and update with curr.id:
  $query = qq|ALTER TABLE ap ADD currency INTEGER;
              ALTER TABLE ar ADD currency INTEGER;
              ALTER TABLE oe ADD currency INTEGER;
              ALTER TABLE customer ADD currency INTEGER;
              ALTER TABLE delivery_orders ADD currency INTEGER;
              ALTER TABLE exchangerate ADD currency INTEGER;
              ALTER TABLE vendor ADD currency INTEGER;
              ALTER TABLE defaults ADD currency INTEGER;|;
  do_query($query);
  #Set defaultcurrency:
  $query = qq|UPDATE defaults SET currency= (SELECT id FROM currencies WHERE curr = '| . $main::form->{defaultcurrency} . qq|')|;
  do_query($query);
  $query = qq|UPDATE ap SET currency = (SELECT id FROM currencies c WHERE c.curr = ap.curr);
              UPDATE ar SET currency = (SELECT id FROM currencies c WHERE c.curr = ar.curr);
              UPDATE oe SET currency = (SELECT id FROM currencies c WHERE c.curr = oe.curr);
              UPDATE customer SET currency = (SELECT id FROM currencies c WHERE c.curr = customer.curr);
              UPDATE delivery_orders SET currency = (SELECT id FROM currencies c WHERE c.curr = delivery_orders.curr);
              UPDATE exchangerate SET currency = (SELECT id FROM currencies c WHERE c.curr = exchangerate.curr);
              UPDATE vendor SET currency = (SELECT id FROM currencies c WHERE c.curr = vendor.curr);|;
  do_query($query);

  #Drop column 'curr':
  $query = qq|ALTER TABLE ap DROP COLUMN curr;
              ALTER TABLE ar DROP COLUMN curr;
              ALTER TABLE oe DROP COLUMN curr;
              ALTER TABLE customer DROP COLUMN curr;
              ALTER TABLE delivery_orders DROP COLUMN curr;
              ALTER TABLE exchangerate DROP COLUMN curr;
              ALTER TABLE vendor DROP COLUMN curr;
              ALTER TABLE defaults DROP COLUMN curr;|;
  do_query($query);

  #Rename currency to curr:
  $query = qq|ALTER TABLE defaults RENAME COLUMN currency TO curr;
              ALTER TABLE ap RENAME COLUMN currency TO curr;
              ALTER TABLE ar RENAME COLUMN currency TO curr;
              ALTER TABLE oe RENAME COLUMN currency TO curr;
              ALTER TABLE customer RENAME COLUMN currency TO curr;
              ALTER TABLE delivery_orders RENAME COLUMN currency TO curr;
              ALTER TABLE exchangerate RENAME COLUMN currency TO curr;
              ALTER TABLE vendor RENAME COLUMN currency TO curr;|;
  do_query($query);

  #Set NOT NULL constraints:
  $query = qq|ALTER TABLE ap ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE ar ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE oe ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE customer ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE delivery_orders ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE exchangerate ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE vendor ALTER COLUMN curr SET NOT NULL;
              ALTER TABLE defaults ALTER COLUMN curr SET NOT NULL;|;
  do_query($query);

  #Set foreign keys:
  $query = qq|ALTER TABLE ap ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE ar ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE oe ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE customer ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE delivery_orders ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE exchangerate ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE vendor ADD FOREIGN KEY (curr) REFERENCES currencies(id);
              ALTER TABLE defaults ADD FOREIGN KEY (curr) REFERENCES currencies(id);|;
  do_query($query);

};

sub print_no_default_currency {
  print $main::form->parse_html_template("dbupgrade/no_default_currency");
};

sub print_orphaned_currencies {
  print $main::form->parse_html_template("dbupgrade/orphaned_currencies");
};

return do_update();
