package SL::Controller::Part;

use strict;
use parent qw(SL::Controller::Base);

use Clone qw(clone);
use SL::DB::Part;
use SL::Controller::Helper::GetModels;
use SL::Locale::String qw(t8);
use SL::JSON;
use List::Util qw(sum);
use SL::Helper::Flash;
use Data::Dumper;
use DateTime;
use SL::DB::History;
use SL::CVar;
use Carp;

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(parts models part p warehouses multi_items_models
                                  makemodels
                                  orphaned
                                  assortment assortment_items assembly assembly_items
                                  all_pricegroups all_translations all_partsgroups all_units
                                  all_buchungsgruppen all_payment_terms all_warehouses
                                  all_languages all_units all_price_factors) ],
  'scalar'                => [ qw(warehouse bin) ],
);

# safety
__PACKAGE__->run_before(sub { $::auth->assert('part_service_assembly_edit') },
                        except => [ qw(ajax_autocomplete part_picker_search part_picker_result) ]);

__PACKAGE__->run_before('check_part_id', only   => [ qw(edit delete) ]);

# actions for editing parts
#
sub action_add_part {
  my ($self, %params) = @_;

  $self->part( SL::DB::Part->new_part );
  $self->add;
};

sub action_add_service {
  my ($self, %params) = @_;

  $self->part( SL::DB::Part->new_service );
  $self->add;
};

sub action_add_assembly {
  my ($self, %params) = @_;

  $self->part( SL::DB::Part->new_assembly );
  $self->add;
};

sub action_add_assortment {
  my ($self, %params) = @_;

  $self->part( SL::DB::Part->new_assortment );
  $self->add;
};

sub action_add {
  my ($self) = @_;

  check_has_valid_part_type($::form->{part_type});

  $self->action_add_part       if $::form->{part_type} eq 'part';
  $self->action_add_service    if $::form->{part_type} eq 'service';
  $self->action_add_assembly   if $::form->{part_type} eq 'assembly';
  $self->action_add_assortment if $::form->{part_type} eq 'assortment';
};

sub action_save {
  my ($self, %params) = @_;

  # checks that depend only on submitted $::form
  $self->check_form or return $self->js->render;

  my $is_new = !$self->part->id; # $ part gets loaded here

  # check that the part hasn't been modified
  unless ( $is_new ) {
    $self->check_part_not_modified or
      return $self->js->error(t8('The document has been changed by another user. Please reopen it in another window and copy the changes to the new window'))->render;
  }

  if ( $is_new and !$::form->{part}{partnumber} ) {
    $self->check_next_transnumber_is_free or return $self->js->error(t8('The next partnumber in the number range already exists!'))->render;
  }

  $self->parse_form;

  my @errors = $self->part->validate;
  return $self->js->error(@errors)->render if @errors;

  # $self->part has been loaded, parsed and validated without errors and is ready to be saved
  $self->part->db->with_transaction(sub {

    if ( $params{save_as_new} ) {
      $self->part( $self->part->clone_and_reset_deep );
      $self->part->partnumber(undef); # will be assigned by _before_save_set_partnumber
    };

    $self->part->save(cascade => 1);

    SL::DB::History->new(
      trans_id    => $self->part->id,
      snumbers    => 'partnumber_' . $self->part->partnumber,
      employee_id => SL::DB::Manager::Employee->current->id,
      what_done   => 'part',
      addition    => 'SAVED',
    )->save();

    CVar->save_custom_variables(
        dbh          => $self->part->db->dbh,
        module       => 'IC',
        trans_id     => $self->part->id,
        variables    => $::form, # $::form->{cvar} would be nicer
        always_valid => 1,
    );

    1;
  }) or return $self->js->error(t8('The item couldn\'t be saved!') . " " . $self->part->db->error )->render;

  flash_later('info', $is_new ? t8('The item has been created.') : t8('The item has been saved.'));

  # reload item, this also resets last_modification!
  $self->redirect_to(controller => 'Part', action => 'edit', 'part.id' => $self->part->id);
}

sub action_save_as_new {
  my ($self) = @_;
  $self->action_save(save_as_new=>1);
}

sub action_delete {
  my ($self) = @_;

  my $db = $self->part->db; # $self->part has a get_set_init on $::form

  my $partnumber = $self->part->partnumber; # remember for history log

  $db->do_transaction(
    sub {

      # delete part, together with relationships that don't already
      # have an ON DELETE CASCADE, e.g. makemodel and translation.
      $self->part->delete(cascade => 1);

      SL::DB::History->new(
        trans_id    => $self->part->id,
        snumbers    => 'partnumber_' . $partnumber,
        employee_id => SL::DB::Manager::Employee->current->id,
        what_done   => 'part',
        addition    => 'DELETED',
      )->save();
      1;
  }) or return $self->js->error(t8('The item couldn\'t be deleted!') . " " . $self->part->db->error)->render;

  flash_later('info', t8('The item has been deleted.'));
  my @redirect_params = (
    controller => 'controller.pl',
    action => 'LoginScreen/user_login'
  );
  $self->redirect_to(@redirect_params);
}

sub action_use_as_new {
  my ($self, %params) = @_;

  my $oldpart = SL::DB::Manager::Part->find_by( id => $::form->{old_id}) or die "can't find old part";
  $::form->{oldpartnumber} = $oldpart->partnumber;

  $self->part($oldpart->clone_and_reset_deep);
  $self->parse_form;
  $self->part->partnumber(undef);

  $self->render_form;
}

sub action_edit {
  my ($self, %params) = @_;

  $self->render_form;
}

sub render_form {
  my ($self, %params) = @_;

  $self->_set_javascript;

  my (%assortment_vars, %assembly_vars);
  %assortment_vars = %{ $self->prepare_assortment_render_vars } if $self->part->is_assortment;
  %assembly_vars   = %{ $self->prepare_assembly_render_vars   } if $self->part->is_assembly;

  $params{CUSTOM_VARIABLES}  = CVar->get_custom_variables(module => 'IC', trans_id => $self->part->id);

  CVar->render_inputs('variables' => $params{CUSTOM_VARIABLES}, show_disabled_message => 1, partsgroup_id => $self->part->partsgroup_id)
    if (scalar @{ $params{CUSTOM_VARIABLES} });

  my %title_hash = ( part       => t8('Edit Part'),
                     assembly   => t8('Edit Assembly'),
                     service    => t8('Edit Service'),
                     assortment => t8('Edit Assortment'),
                   );

  $self->part->prices([])       unless $self->part->prices;
  $self->part->translations([]) unless $self->part->translations;

  $self->render(
    'part/form',
    title             => $title_hash{$self->part->part_type},
    show_edit_buttons => $::auth->assert('part_service_assembly_edit'),
    %assortment_vars,
    %assembly_vars,
    translations_map  => { map { ($_->language_id   => $_) } @{$self->part->translations} },
    prices_map        => { map { ($_->pricegroup_id => $_) } @{$self->part->prices      } },
    oldpartnumber     => $::form->{oldpartnumber},
    old_id            => $::form->{old_id},
    %params,
  );
}

sub action_history {
  my ($self) = @_;

  my $history_entries = SL::DB::Part->new(id => $::form->{part}{id})->history_entries;
  $_[0]->render('part/history', { layout => 0 },
                                  history_entries => $history_entries);
}

sub action_update_item_totals {
  my ($self) = @_;

  my $part_type = $::form->{part_type};
  die unless $part_type =~ /^(assortment|assembly)$/;

  my $sellprice_sum = $self->recalc_item_totals(part_type => $part_type, price_type => 'sellcost');
  my $lastcost_sum  = $self->recalc_item_totals(part_type => $part_type, price_type => 'lastcost');

  my $sum_diff      = $sellprice_sum-$lastcost_sum;

  $self->js
    ->html('#items_sellprice_sum',       $::form->format_amount(\%::myconfig, $sellprice_sum, 2, 0))
    ->html('#items_lastcost_sum',        $::form->format_amount(\%::myconfig, $lastcost_sum,  2, 0))
    ->html('#items_sum_diff',            $::form->format_amount(\%::myconfig, $sum_diff,      2, 0))
    ->html('#items_sellprice_sum_basic', $::form->format_amount(\%::myconfig, $sellprice_sum, 2, 0))
    ->html('#items_lastcost_sum_basic',  $::form->format_amount(\%::myconfig, $lastcost_sum,  2, 0))
    ->render();
}

sub action_add_multi_assortment_items {
  my ($self) = @_;

  my $item_objects = $self->parse_add_items_to_objects(part_type => 'assortment');
  my $html         = $self->render_assortment_items_to_html($item_objects);

  $self->js->run('kivi.Part.close_multi_items_dialog')
           ->append('#assortment_rows', $html)
           ->run('kivi.Part.renumber_positions')
           ->run('kivi.Part.assortment_recalc')
           ->render();
}

sub action_add_multi_assembly_items {
  my ($self) = @_;

  my $item_objects = $self->parse_add_items_to_objects(part_type => 'assembly');
  my $html         = $self->render_assembly_items_to_html($item_objects);

  $self->js->run('kivi.Part.close_multi_items_dialog')
           ->append('#assembly_rows', $html)
           ->run('kivi.Part.renumber_positions')
           ->run('kivi.Part.assembly_recalc')
           ->render();
}

sub action_add_assortment_item {
  my ($self, %params) = @_;

  validate_add_items() or return $self->js->error(t8("No part was selected."))->render;

  carp('Too many objects passed to add_assortment_item') if @{$::form->{add_items}} > 1;

  my $add_item_id = $::form->{add_items}->[0]->{parts_id};
  if ( $add_item_id && grep { $add_item_id == $_->parts_id } @{ $self->assortment_items } ) {
    return $self->js->flash('error', t8("This part has already been added."))->render;
  };

  my $number_of_items = scalar @{$self->assortment_items};
  my $item_objects    = $self->parse_add_items_to_objects(part_type => 'assortment');
  my $html            = $self->render_assortment_items_to_html($item_objects, $number_of_items);

  push(@{$self->assortment_items}, @{$item_objects});
  my $part = SL::DB::Part->new(part_type => 'assortment');
  $part->assortment_items(@{$self->assortment_items});
  my $items_sellprice_sum = $part->items_sellprice_sum;
  my $items_lastcost_sum  = $part->items_lastcost_sum;
  my $items_sum_diff      = $items_sellprice_sum - $items_lastcost_sum;

  $self->js
    ->append('#assortment_rows'        , $html)  # append in tbody
    ->val('.add_assortment_item_input' , '')
    ->run('kivi.Part.focus_last_assortment_input')
    ->html("#items_sellprice_sum", $::form->format_amount(\%::myconfig, $items_sellprice_sum, 2, 0))
    ->html("#items_lastcost_sum",  $::form->format_amount(\%::myconfig, $items_lastcost_sum,  2, 0))
    ->html("#items_sum_diff",      $::form->format_amount(\%::myconfig, $items_sum_diff,      2, 0))
    ->html('#items_sellprice_sum_basic', $::form->format_amount(\%::myconfig, $items_sellprice_sum, 2, 0))
    ->html('#items_lastcost_sum_basic',  $::form->format_amount(\%::myconfig, $items_lastcost_sum,  2, 0))
    ->render;
}
sub action_add_assembly_item {
  my ($self) = @_;

  validate_add_items() or return $self->js->error(t8("No part was selected."))->render;

  carp('Too many objects passed to add_assembly_item') if @{$::form->{add_items}} > 1;

  my $add_item_id = $::form->{add_items}->[0]->{parts_id};
  my $duplicate_warning = 0; # duplicates are allowed, just warn
  if ( $add_item_id && grep { $add_item_id == $_->parts_id } @{ $self->assembly_items } ) {
    $duplicate_warning++;
  };

  my $number_of_items = scalar @{$self->assembly_items};
  my $item_objects    = $self->parse_add_items_to_objects(part_type => 'assembly');
  my $html            = $self->render_assembly_items_to_html($item_objects, $number_of_items);

  $self->js->flash('info', t8("This part has already been added.")) if $duplicate_warning;

  push(@{$self->assembly_items}, @{$item_objects});
  my $part = SL::DB::Part->new(part_type => 'assembly');
  $part->assemblies(@{$self->assembly_items});
  my $items_sellprice_sum = $part->items_sellprice_sum;
  my $items_lastcost_sum  = $part->items_lastcost_sum;
  my $items_sum_diff      = $items_sellprice_sum - $items_lastcost_sum;

  $self->js
    ->append('#assembly_rows', $html)  # append in tbody
    ->val('.add_assembly_item_input' , '')
    ->run('kivi.Part.focus_last_assembly_input')
    ->html('#items_sellprice_sum', $::form->format_amount(\%::myconfig, $items_sellprice_sum, 2, 0))
    ->html('#items_lastcost_sum' , $::form->format_amount(\%::myconfig, $items_lastcost_sum , 2, 0))
    ->html('#items_sum_diff',      $::form->format_amount(\%::myconfig, $items_sum_diff     , 2, 0))
    ->html('#items_sellprice_sum_basic', $::form->format_amount(\%::myconfig, $items_sellprice_sum, 2, 0))
    ->html('#items_lastcost_sum_basic' , $::form->format_amount(\%::myconfig, $items_lastcost_sum , 2, 0))
    ->render;
}

sub action_show_multi_items_dialog {
  require SL::DB::PartsGroup;
  $_[0]->render('part/_multi_items_dialog', { layout => 0 },
                part_type => 'assortment',
                partfilter => '', # can I get at the current input of the partpicker here?
                all_partsgroups => SL::DB::Manager::PartsGroup->get_all);
}

sub action_multi_items_update_result {
  my $max_count = 100;

  $::form->{multi_items}->{filter}->{obsolete} = 0;

  my $count = $_[0]->multi_items_models->count;

  if ($count == 0) {
    my $text = SL::Presenter::EscapedText->new(text => $::locale->text('No results.'));
    $_[0]->render($text, { layout => 0 });
  } elsif ($count > $max_count) {
    my $text = SL::Presenter::EscapedText->new(text => $::locale->text('Too many results (#1 from #2).', $count, $max_count));
    $_[0]->render($text, { layout => 0 });
  } else {
    my $multi_items = $_[0]->multi_items_models->get;
    $_[0]->render('part/_multi_items_result', { layout => 0 },
                  multi_items => $multi_items);
  }
}

sub action_add_makemodel_row {
  my ($self) = @_;

  my $vendor_id = $::form->{add_makemodel};

  my $vendor = SL::DB::Manager::Vendor->find_by(id => $vendor_id) or
    return $self->js->error(t8("No vendor selected or found!"))->render;

  if ( grep { $vendor_id == $_->make } @{ $self->makemodels } ) {
    $self->js->flash('info', t8("This vendor has already been added."));
  };

  my $position = scalar @{$self->makemodels} + 1;

  my $mm = SL::DB::MakeModel->new(# parts_id    => $::form->{part}->{id},
                                  make        => $vendor->id,
                                  model       => '',
                                  lastcost    => 0,
                                  sortorder    => $position,
                                 ) or die "Can't create MakeModel object";

  my $row_as_html = $self->p->render('part/_makemodel_row',
                                     makemodel => $mm,
                                     listrow   => $position % 2 ? 0 : 1,
  );

  # after selection focus on the model field in the row that was just added
  $self->js
    ->append('#makemodel_rows', $row_as_html)  # append in tbody
    ->val('.add_makemodel_input', '')
    ->run('kivi.Part.focus_last_makemodel_input')
    ->render;
}

sub action_reorder_items {
  my ($self) = @_;

  my $part_type = $::form->{part_type};

  my %sort_keys = (
    partnumber  => sub { $_[0]->part->partnumber },
    description => sub { $_[0]->part->description },
    qty         => sub { $_[0]->qty },
    sellprice   => sub { $_[0]->part->sellprice },
    lastcost    => sub { $_[0]->part->lastcost },
    partsgroup  => sub { $_[0]->part->partsgroup_id ? $_[0]->part->partsgroup->partsgroup : '' },
  );

  my $method = $sort_keys{$::form->{order_by}};

  my @items;
  if ($part_type eq 'assortment') {
    @items = @{ $self->assortment_items };
  } else {
    @items = @{ $self->assembly_items };
  };

  my @to_sort = map { { old_pos => $_->position, order_by => $method->($_) } } @items;
  if ($::form->{order_by} =~ /^(qty|sellprice|lastcost)$/) {
    if ($::form->{sort_dir}) {
      @to_sort = sort { $a->{order_by} <=> $b->{order_by} } @to_sort;
    } else {
      @to_sort = sort { $b->{order_by} <=> $a->{order_by} } @to_sort;
    }
  } else {
    if ($::form->{sort_dir}) {
      @to_sort = sort { $a->{order_by} cmp $b->{order_by} } @to_sort;
    } else {
      @to_sort = sort { $b->{order_by} cmp $a->{order_by} } @to_sort;
    }
  };

  $self->js->run('kivi.Part.redisplay_items', \@to_sort)->render;
}

sub action_warehouse_changed {
  my ($self) = @_;

  $self->warehouse(SL::DB::Manager::Warehouse->find_by_or_create(id => $::form->{warehouse_id}));
  die unless ref($self->warehouse) eq 'SL::DB::Warehouse';

  if ( $self->warehouse->id and @{$self->warehouse->bins} ) {
    $self->bin($self->warehouse->bins->[0]);
    $self->js
      ->html('#bin', $self->build_bin_select)
      ->focus('#part_bin_id');
  } else {
    # no warehouse was selected, empty the bin field and reset the id
    $self->js
        ->val('#part_bin_id', undef)
        ->html('#bin', '');
  };

  return $self->js->render;
}

sub action_ajax_autocomplete {
  my ($self, %params) = @_;

  # if someone types something, and hits enter, assume he entered the full name.
  # if something matches, treat that as sole match
  # unfortunately get_models can't do more than one per package atm, so we d it
  # the oldfashioned way.
  if ($::form->{prefer_exact}) {
    my $exact_matches;
    if (1 == scalar @{ $exact_matches = SL::DB::Manager::Part->get_all(
      query => [
        obsolete => 0,
        SL::DB::Manager::Part->type_filter($::form->{filter}{part_type}),
        or => [
          description => { ilike => $::form->{filter}{'all:substr:multi::ilike'} },
          partnumber  => { ilike => $::form->{filter}{'all:substr:multi::ilike'} },
        ]
      ],
      limit => 2,
    ) }) {
      $self->parts($exact_matches);
    }
  }

  my @hashes = map {
   +{
     value       => $_->displayable_name,
     label       => $_->displayable_name,
     id          => $_->id,
     partnumber  => $_->partnumber,
     description => $_->description,
     part_type   => $_->part_type,
     unit        => $_->unit,
     cvars       => { map { ($_->config->name => { value => $_->value_as_text, is_valid => $_->is_valid }) } @{ $_->cvars_by_config } },
    }
  } @{ $self->parts }; # neato: if exact match triggers we don't even need the init_parts

  $self->render(\ SL::JSON::to_json(\@hashes), { layout => 0, type => 'json', process => 0 });
}

sub action_test_page {
  $_[0]->render('part/test_page', pre_filled_part => SL::DB::Manager::Part->get_first);
}

sub action_part_picker_search {
  $_[0]->render('part/part_picker_search', { layout => 0 }, parts => $_[0]->parts);
}

sub action_part_picker_result {
  $_[0]->render('part/_part_picker_result', { layout => 0 });
}

sub action_show {
  my ($self) = @_;

  if ($::request->type eq 'json') {
    my $part_hash;
    if (!$self->part) {
      # TODO error
    } else {
      $part_hash          = $self->part->as_tree;
      $part_hash->{cvars} = $self->part->cvar_as_hashref;
    }

    $self->render(\ SL::JSON::to_json($part_hash), { layout => 0, type => 'json', process => 0 });
  }
}

# helper functions
sub validate_add_items {
  scalar @{$::form->{add_items}};
}

sub prepare_assortment_render_vars {
  my ($self) = @_;

  my %vars = ( items_sellprice_sum => $self->part->items_sellprice_sum,
               items_lastcost_sum  => $self->part->items_lastcost_sum,
               assortment_html     => $self->render_assortment_items_to_html( \@{$self->part->items} ),
             );
  $vars{items_sum_diff} = $vars{items_sellprice_sum} - $vars{items_lastcost_sum};

  return \%vars;
}

sub prepare_assembly_render_vars {
  my ($self) = @_;

  my %vars = ( items_sellprice_sum => $self->part->items_sellprice_sum,
               items_lastcost_sum  => $self->part->items_lastcost_sum,
               assembly_html       => $self->render_assembly_items_to_html( \@{ $self->part->items } ),
             );
  $vars{items_sum_diff} = $vars{items_sellprice_sum} - $vars{items_lastcost_sum};

  return \%vars;
}

sub add {
  my ($self) = @_;

  check_has_valid_part_type($self->part->part_type);

  $self->_set_javascript;

  my %title_hash = ( part       => t8('Add Part'),
                     assembly   => t8('Add Assembly'),
                     service    => t8('Add Service'),
                     assortment => t8('Add Assortment'),
                   );

  $self->render(
    'part/form',
    title             => $title_hash{$self->part->part_type},
    show_edit_buttons => $::auth->assert('part_service_assembly_edit'),
  );
}


sub _set_javascript {
  my ($self) = @_;
  $::request->layout->use_javascript("${_}.js")  for qw(kivi.Part kivi.PriceRule ckeditor/ckeditor ckeditor/adapters/jquery);
  $::request->layout->add_javascripts_inline("\$(function(){kivi.PriceRule.load_price_rules_for_part(@{[ $self->part->id ]})});") if $self->part->id;
}

sub recalc_item_totals {
  my ($self, %params) = @_;

  if ( $params{part_type} eq 'assortment' ) {
    return 0 unless scalar @{$self->assortment_items};
  } elsif ( $params{part_type} eq 'assembly' ) {
    return 0 unless scalar @{$self->assembly_items};
  } else {
    carp "can only calculate sum for assortments and assemblies";
  };

  my $part = SL::DB::Part->new(part_type => $params{part_type});
  if ( $part->is_assortment ) {
    $part->assortment_items( @{$self->assortment_items} );
    if ( $params{price_type} eq 'lastcost' ) {
      return $part->items_lastcost_sum;
    } else {
      if ( $params{pricegroup_id} ) {
        return $part->items_sellprice_sum(pricegroup_id => $params{pricegroup_id});
      } else {
        return $part->items_sellprice_sum;
      };
    }
  } elsif ( $part->is_assembly ) {
    $part->assemblies( @{$self->assembly_items} );
    if ( $params{price_type} eq 'lastcost' ) {
      return $part->items_lastcost_sum;
    } else {
      return $part->items_sellprice_sum;
    }
  }
}

sub check_part_not_modified {
  my ($self) = @_;

  return !($::form->{last_modification} && ($self->part->last_modification ne $::form->{last_modification}));

}

sub parse_form {
  my ($self) = @_;

  my $is_new = !$self->part->id;

  my $params = delete($::form->{part}) || { };

  delete $params->{id};
  # never overwrite existing partnumber, should be a read-only field anyway
  delete $params->{partnumber} if $self->part->partnumber;
  $self->part->assign_attributes(%{ $params});
  $self->part->bin_id(undef) unless $self->part->warehouse_id;

  # Only reset items ([]) and rewrite from form if $::form->{assortment_items} isn't empty. This
  # will be the case for used assortments when saving, or when a used assortment
  # is "used as new"
  if ( $self->part->is_assortment and $::form->{assortment_items} and scalar @{$::form->{assortment_items}}) {
    $self->part->assortment_items([]);
    $self->part->add_assortment_items(@{$self->assortment_items}); # assortment_items has a get_set_init
  };

  if ( $self->part->is_assembly and $::form->{assembly_items} and @{$::form->{assembly_items}} ) {
    $self->part->assemblies([]); # completely rewrite assortments each time
    $self->part->add_assemblies( @{ $self->assembly_items } );
  };

  $self->part->translations([]);
  $self->parse_form_translations;

  $self->part->prices([]);
  $self->parse_form_prices;

  $self->parse_form_makemodels;
}

sub parse_form_prices {
  my ($self) = @_;
  # only save prices > 0
  my $prices = delete($::form->{prices}) || [];
  foreach my $price ( @{$prices} ) {
    my $sellprice = $::form->parse_amount(\%::myconfig, $price->{price});
    next unless $sellprice > 0; # skip negative prices as well
    my $p = SL::DB::Price->new(parts_id      => $self->part->id,
                               pricegroup_id => $price->{pricegroup_id},
                               price         => $sellprice,
                              );
    $self->part->add_prices($p);
  };
}

sub parse_form_translations {
  my ($self) = @_;
  # don't add empty translations
  my $translations = delete($::form->{translations}) || [];
  foreach my $translation ( @{$translations} ) {
    next unless $translation->{translation};
    my $t = SL::DB::Translation->new( %{$translation} ) or die "Can't create translation";
    $self->part->add_translations( $translation );
  };
}

sub parse_form_makemodels {
  my ($self) = @_;

  my $makemodels_map;
  if ( $self->part->makemodels ) { # check for new parts or parts without makemodels
    $makemodels_map = { map { $_->id => Rose::DB::Object::Helpers::clone($_) } @{$self->part->makemodels} };
  };

  $self->part->makemodels([]);

  my $position = 0;
  my $makemodels = delete($::form->{makemodels}) || [];
  foreach my $makemodel ( @{$makemodels} ) {
    next unless $makemodel->{make};
    $position++;
    my $vendor = SL::DB::Manager::Vendor->find_by(id => $makemodel->{make}) || die "Can't find vendor from make";

    my $mm = SL::DB::MakeModel->new( # parts_id   => $self->part->id, # will be assigned by row add_makemodels
                                     id         => $makemodel->{id},
                                     make       => $makemodel->{make},
                                     model      => $makemodel->{model} || '',
                                     lastcost   => $::form->parse_amount(\%::myconfig, $makemodel->{lastcost_as_number}),
                                     sortorder  => $position,
                                   );
    if ($makemodels_map->{$mm->id} && !$makemodels_map->{$mm->id}->lastupdate && $makemodels_map->{$mm->id}->lastcost == 0 && $mm->lastcost == 0) {
      # lastupdate isn't set, original lastcost is 0 and new lastcost is 0
      # don't change lastupdate
    } elsif ( !$makemodels_map->{$mm->id} && $mm->lastcost == 0 ) {
      # new makemodel, no lastcost entered, leave lastupdate empty
    } elsif ($makemodels_map->{$mm->id} && $makemodels_map->{$mm->id}->lastcost == $mm->lastcost) {
      # lastcost hasn't changed, use original lastupdate
      $mm->lastupdate($makemodels_map->{$mm->id}->lastupdate);
    } else {
      $mm->lastupdate(DateTime->now);
    };
    $self->part->makemodel( scalar @{$self->part->makemodels} ? 1 : 0 ); # do we need this boolean anymore?
    $self->part->add_makemodels($mm);
  };
}

sub build_bin_select {
  $_[0]->p->select_tag('part.bin_id', [ $_[0]->warehouse->bins ],
    title_key => 'description',
    default   => $_[0]->bin->id,
  );
}

# get_set_inits for partpicker

sub init_parts {
  if ($::form->{no_paginate}) {
    $_[0]->models->disable_plugin('paginated');
  }

  $_[0]->models->get;
}

# get_set_inits for part controller
sub init_part {
  my ($self) = @_;

  # used by edit, save, delete and add

  if ( $::form->{part}{id} ) {
    return SL::DB::Part->new(id => $::form->{part}{id})->load(with => [ qw(makemodels prices translations partsgroup) ]);
  } else {
    die "part_type missing" unless $::form->{part}{part_type};
    return SL::DB::Part->new(part_type => $::form->{part}{part_type});
  };
}

sub init_orphaned {
  my ($self) = @_;
  return $self->part->orphaned;
}

sub init_models {
  my ($self) = @_;

  SL::Controller::Helper::GetModels->new(
    controller => $self,
    sorted => {
      _default  => {
        by => 'partnumber',
        dir  => 1,
      },
      partnumber  => t8('Partnumber'),
      description  => t8('Description'),
    },
    with_objects => [ qw(unit_obj) ],
  );
}

sub init_p {
  SL::Presenter->get;
}


sub init_assortment_items {
  # this init is used while saving and whenever assortments change dynamically
  my ($self) = @_;
  my $position = 0;
  my @array;
  my $assortment_items = delete($::form->{assortment_items}) || [];
  foreach my $assortment_item ( @{$assortment_items} ) {
    next unless $assortment_item->{parts_id};
    $position++;
    my $part = SL::DB::Manager::Part->find_by(id => $assortment_item->{parts_id}) || die "Can't determine item to be added";
    my $ai = SL::DB::AssortmentItem->new( parts_id      => $part->id,
                                          qty           => $::form->parse_amount(\%::myconfig, $assortment_item->{qty_as_number}),
                                          charge        => $assortment_item->{charge},
                                          unit          => $assortment_item->{unit} || $part->unit,
                                          position      => $position,
    );

    push(@array, $ai);
  };
  return \@array;
}

sub init_makemodels {
  my ($self) = @_;

  my $position = 0;
  my @makemodel_array = ();
  my $makemodels = delete($::form->{makemodels}) || [];

  foreach my $makemodel ( @{$makemodels} ) {
    next unless $makemodel->{make};
    $position++;
    my $mm = SL::DB::MakeModel->new( # parts_id   => $self->part->id, # will be assigned by row add_makemodels
                                    id        => $makemodel->{id},
                                    make      => $makemodel->{make},
                                    model     => $makemodel->{model} || '',
                                    lastcost  => $::form->parse_amount(\%::myconfig, $makemodel->{lastcost_as_number} || 0),
                                    sortorder => $position,
                                  ) or die "Can't create mm";
    # $mm->id($makemodel->{id}) if $makemodel->{id};
    push(@makemodel_array, $mm);
  };
  return \@makemodel_array;
}

sub init_assembly_items {
  my ($self) = @_;
  my $position = 0;
  my @array;
  my $assembly_items = delete($::form->{assembly_items}) || [];
  foreach my $assembly_item ( @{$assembly_items} ) {
    next unless $assembly_item->{parts_id};
    $position++;
    my $part = SL::DB::Manager::Part->find_by(id => $assembly_item->{parts_id}) || die "Can't determine item to be added";
    my $ai = SL::DB::Assembly->new(parts_id    => $part->id,
                                   bom         => $assembly_item->{bom},
                                   qty         => $::form->parse_amount(\%::myconfig, $assembly_item->{qty_as_number}),
                                   position    => $position,
                                  );
    push(@array, $ai);
  };
  return \@array;
}

sub init_all_warehouses {
  my ($self) = @_;
  SL::DB::Manager::Warehouse->get_all(query => [ or => [ invalid => 0, invalid => undef, id => $self->part->warehouse_id ] ]);
}

sub init_all_languages {
  SL::DB::Manager::Language->get_all_sorted;
}

sub init_all_partsgroups {
  SL::DB::Manager::PartsGroup->get_all_sorted;
}

sub init_all_buchungsgruppen {
  my ($self) = @_;
  if ( $self->part->orphaned ) {
    return SL::DB::Manager::Buchungsgruppe->get_all_sorted;
  } else {
    return SL::DB::Manager::Buchungsgruppe->get_all(where => [ id => $self->part->buchungsgruppen_id ]);
  }
}

sub init_all_units {
  my ($self) = @_;
  if ( $self->part->orphaned ) {
    return SL::DB::Manager::Unit->get_all_sorted;
  } else {
    return SL::DB::Manager::Unit->get_all(where => [ unit => $self->part->unit ]);
  }
}

sub init_all_payment_terms {
  SL::DB::Manager::PaymentTerm->get_all_sorted;
}

sub init_all_price_factors {
  SL::DB::Manager::PriceFactor->get_all_sorted;
}

sub init_all_pricegroups {
  SL::DB::Manager::Pricegroup->get_all_sorted;
}

# model used to filter/display the parts in the multi-items dialog
sub init_multi_items_models {
  SL::Controller::Helper::GetModels->new(
    controller     => $_[0],
    model          => 'Part',
    with_objects   => [ qw(unit_obj partsgroup) ],
    disable_plugin => 'paginated',
    source         => $::form->{multi_items},
    sorted         => {
      _default    => {
        by  => 'partnumber',
        dir => 1,
      },
      partnumber  => t8('Partnumber'),
      description => t8('Description')}
  );
}

# simple checks to run on $::form before saving

sub form_check_part_description_exists {
  my ($self) = @_;

  return 1 if $::form->{part}{description};

  $self->js->flash('error', t8('Part Description missing!'))
           ->run('kivi.Part.set_tab_active_by_name', 'basic_data')
           ->focus('#part_description');
  return 0;
}

sub form_check_assortment_items_exist {
  my ($self) = @_;

  return 1 unless $::form->{part}{part_type} eq 'assortment';
  # skip check for existing parts that have been used
  return 1 if ($self->part->id and !$self->part->orphaned);

  # new or orphaned parts must have items in $::form->{assortment_items}
  unless ( $::form->{assortment_items} and scalar @{$::form->{assortment_items}} ) {
    $self->js->run('kivi.Part.set_tab_active_by_name', 'assortment_tab')
             ->focus('#add_assortment_item_name')
             ->flash('error', t8('The assortment doesn\'t have any items.'));
    return 0;
  };
  return 1;
}

sub form_check_assortment_items_unique {
  my ($self) = @_;

  return 1 unless $::form->{part}{part_type} eq 'assortment';

  my %duplicate_elements;
  my %count;
  for (map { $_->{parts_id} } @{$::form->{assortment_items}}) {
    $duplicate_elements{$_}++ if $count{$_}++;
  };

  if ( keys %duplicate_elements ) {
    $self->js->run('kivi.Part.set_tab_active_by_name', 'assortment_tab')
             ->flash('error', t8('There are duplicate assortment items'));
    return 0;
  };
  return 1;
}

sub form_check_assembly_items_exist {
  my ($self) = @_;

  return 1 unless $::form->{part}->{part_type} eq 'assembly';

  unless ( $::form->{assembly_items} and scalar @{$::form->{assembly_items}} ) {
    $self->js->run('kivi.Part.set_tab_active_by_name', 'assembly_tab')
             ->focus('#add_assembly_item_name')
             ->flash('error', t8('The assembly doesn\'t have any items.'));
    return 0;
  };
  return 1;
}

sub form_check_partnumber_is_unique {
  my ($self) = @_;

  if ( !$::form->{part}{id} and $::form->{part}{partnumber} ) {
    my $count = SL::DB::Manager::Part->get_all_count(where => [ partnumber => $::form->{part}{partnumber} ]);
    if ( $count ) {
      $self->js->flash('error', t8('The partnumber already exists!'))
               ->focus('#part_description');
      return 0;
    };
  };
  return 1;
}

# general checking functions
sub check_next_transnumber_is_free {
  my ($self) = @_;

  my ($next_transnumber, $count);
  $self->part->db->with_transaction(sub {
    $next_transnumber = $self->part->get_next_trans_number;
    $count = SL::DB::Manager::Part->get_all_count(where => [ partnumber => $next_transnumber ]);
    return 1;
  }) or die $@;
  $count ? return 0 : return 1;
}

sub check_part_id {
  die t8("Can't load item without a valid part.id") . "\n" unless $::form->{part}{id};
}

sub check_form {
  my ($self) = @_;

  $self->form_check_part_description_exists || return 0;
  $self->form_check_assortment_items_exist  || return 0;
  $self->form_check_assortment_items_unique || return 0;
  $self->form_check_assembly_items_exist    || return 0;
  $self->form_check_partnumber_is_unique    || return 0;

  return 1;
}

sub check_has_valid_part_type {
  die "invalid part_type" unless $_[0] =~ /^(part|service|assembly|assortment)$/;
}

sub render_assortment_items_to_html {
  my ($self, $assortment_items, $number_of_items) = @_;

  my $position = $number_of_items + 1;
  my $html;
  foreach my $ai (@$assortment_items) {
    $html .= $self->p->render('part/_assortment_row',
                              PART     => $self->part,
                              orphaned => $self->orphaned,
                              ITEM     => $ai,
                              listrow  => $position % 2 ? 1 : 0,
                              position => $position, # for legacy assemblies
                             );
    $position++;
  };
  return $html;
}

sub render_assembly_items_to_html {
  my ($self, $assembly_items, $number_of_items) = @_;

  my $position = $number_of_items + 1;
  my $html;
  foreach my $ai (@{$assembly_items}) {
    $html .= $self->p->render('part/_assembly_row',
                              PART     => $self->part,
                              orphaned => $self->orphaned,
                              ITEM     => $ai,
                              listrow  => $position % 2 ? 1 : 0,
                              position => $position, # for legacy assemblies
                             );
    $position++;
  };
  return $html;
}

sub parse_add_items_to_objects {
  my ($self, %params) = @_;
  my $part_type = $params{part_type};
  die unless $params{part_type} =~ /^(assortment|assembly)$/;
  my $position = $params{position} || 1;

  my @add_items = grep { $_->{qty_as_number} } @{ $::form->{add_items} };

  my @item_objects;
  foreach my $item ( @add_items ) {
    my $part = SL::DB::Manager::Part->find_by(id => $item->{parts_id}) || die "Can't load part";
    my $ai;
    if ( $part_type eq 'assortment' ) {
       $ai = SL::DB::AssortmentItem->new(part          => $part,
                                         qty           => $::form->parse_amount(\%::myconfig, $item->{qty_as_number}),
                                         unit          => $part->unit, # TODO: $item->{unit} || $part->unit
                                         position      => $position,
                                        ) or die "Can't create AssortmentItem from item";
    } elsif ( $part_type eq 'assembly' ) {
      $ai = SL::DB::Assembly->new(parts_id    => $part->id,
                                 # id          => $self->assembly->id, # will be set on save
                                 qty         => $::form->parse_amount(\%::myconfig, $item->{qty_as_number}),
                                 bom         => 0, # default when adding: no bom
                                 position    => $position,
                                );
    } else {
      die "part_type must be assortment or assembly";
    }
    push(@item_objects, $ai);
    $position++;
  };

  return \@item_objects;
}

1;

__END__

=encoding utf-8

=head1 NAME

SL::Controller::Part - Part CRUD controller

=head1 DESCRIPTION

Controller for adding/editing/saving/deleting parts.

All the relations are loaded at once and saving the part, adding a history
entry and saving CVars happens inside one transaction.  When saving the old
relations are deleted and written as new to the database.

Relations for parts:

=over 2

=item makemodels

=item translations

=item assembly items

=item assortment items

=item prices

=back

=head1 PART_TYPES

There are 4 different part types:

=over 4

=item C<part>

The "default" part type.

inventory_accno_id is set.

=item C<service>

Services can't be stocked.

inventory_accno_id isn't set.

=item C<assembly>

Assemblies consist of other parts, services, assemblies or assortments. They
aren't meant to be bought, only sold. To add assemblies to stock you typically
have to make them, which reduces the stock by its respective components. Once
an assembly item has been created there is currently no way to "disassemble" it
again. An assembly item can appear several times in one assembly. An assmbly is
sold as one item with a defined sellprice and lastcost. If the component prices
change the assortment price remains the same. The assembly items may be printed
in a record if the item's "bom" is set.

=item C<assortment>

Similar to assembly, but each assortment item may only appear once per
assortment. When selling an assortment the assortment items are added to the
record together with the assortment, which is added with sellprice 0.

Technically an assortment doesn't have a sellprice, but rather the sellprice is
determined by the sum of the current assortment item prices when the assortment
is added to a record. This also means that price rules and customer discounts
will be applied to the assortment items.

Once the assortment items have been added they may be modified or deleted, just
as if they had been added manually, the individual assortment items aren't
linked to the assortment or the other assortment items in any way.

=back

=head1 URL ACTIONS

=over 4

=item C<action_add_part>

=item C<action_add_service>

=item C<action_add_assembly>

=item C<action_add_assortment>

=item C<action_add PART_TYPE>

An alternative to the action_add_$PART_TYPE actions, takes the mandatory
parameter part_type as an action. Example:

  controller.pl?action=Part/add&part_type=service

=item C<action_save>

Saves the current part and then reloads the edit page for the part.

=item C<action_use_as_new>

Takes the information from the current part, plus any modifications made on the
page, and creates a new edit page that is ready to be saved. The partnumber is
set empty, so a new partnumber from the number range will be used if the user
doesn't enter one manually.

Unsaved changes to the original part aren't updated.

The part type cannot be changed in this way.

=item C<action_delete>

Deletes the current part and then redirects to the main page, there is no
callback.

The delete button only appears if the part is 'orphaned', according to
SL::DB::Part orphaned.

The part can't be deleted if it appears in invoices, orders, delivery orders,
the inventory, or is part of an assembly or assortment.

If the part is deleted its relations prices, makdemodel, assembly,
assortment_items and translation are are also deleted via DELETE ON CASCADE.

Before this controller items that appeared in inventory didn't count as
orphaned and could be deleted and the inventory entries were also deleted, this
"feature" hasn't been implemented.

=item C<action_edit part.id>

Load and display a part for editing.

  controller.pl?action=Part/edit&part.id=12345

Passing the part id is mandatory, and the parameter is "part.id", not "id".

=back

=head1 BUTTON ACTIONS

=over 4

=item C<history>

Opens a popup displaying all the history entries. Once a new history controller
is written the button could link there instead, with the part already selected.

=back

=head1 AJAX ACTIONS

=over 4

=item C<action_update_item_totals>

Is called whenever an element with the .recalc class loses focus, e.g. the qty
amount of an item changes. The sum of all sellprices and lastcosts is
calculated and the totals updated. Uses C<recalc_item_totals>.

=item C<action_add_assortment_item>

Adds a new assortment item from a part picker seleciton to the assortment item list

If the item already exists in the assortment the item isn't added and a Flash
error shown.

Rather than running kivi.Part.renumber_positions and kivi.Part.assembly_recalc
after adding each new item, add the new object to the item objects that were
already parsed, calculate totals via a dummy part then update the row and the
totals.

=item C<action_add_assembly_item>

Adds a new assembly item from a part picker seleciton to the assembly item list

If the item already exists in the assembly a flash info is generated, but the
item is added.

Rather than running kivi.Part.renumber_positions and kivi.Part.assembly_recalc
after adding each new item, add the new object to the item objects that were
already parsed, calculate totals via a dummy part then update the row and the
totals.

=item C<action_add_multi_assortment_items>

Parses the items to be added from the form generated by the multi input and
appends the html of the tr-rows to the assortment item table. Afterwards all
assortment items are renumbered and the sums recalculated via
kivi.Part.renumber_positions and kivi.Part.assortment_recalc.

=item C<action_add_multi_assembly_items>

Parses the items to be added from the form generated by the multi input and
appends the html of the tr-rows to the assembly item table. Afterwards all
assembly items are renumbered and the sums recalculated via
kivi.Part.renumber_positions and kivi.Part.assembly_recalc.

=item C<action_show_multi_items_dialog>

=item C<action_multi_items_update_result>

=item C<action_add_makemodel_row>

Add a new makemodel row with the vendor that was selected via the vendor
picker.

Checks the already existing makemodels and warns if a row with that vendor
already exists. Currently it is possible to have duplicate vendor rows.

=item C<action_reorder_items>

Sorts the item table for assembly or assortment items.

=item C<action_warehouse_changed>

=back

=head1 ACTIONS part picker

=over 4

=item C<action_ajax_autocomplete>

=item C<action_test_page>

=item C<action_part_picker_search>

=item C<action_part_picker_result>

=item C<action_show>

=back

=head1 FORM CHECKS

=over 2

=item C<check_form>

Calls some simple checks that test the submitted $::form for obvious errors.
Return 1 if all the tests were successfull, 0 as soon as one test fails.

Errors from the failed tests are stored as ClientJS actions in $self->js. In
some cases extra actions are taken, e.g. if the part description is missing the
basic data tab is selected and the description input field is focussed.

=back

=over 4

=item C<form_check_part_description_exists>

=item C<form_check_assortment_items_exist>

=item C<form_check_assortment_items_unique>

=item C<form_check_assembly_items_exist>

=item C<form_check_partnumber_is_unique>

=back

=head1 HELPER FUNCTIONS

=over 4

=item C<parse_form>

When submitting the form for saving, parses the transmitted form. Expects the
following data:

 $::form->{part}
 $::form->{makemodels}
 $::form->{translations}
 $::form->{prices}
 $::form->{assemblies}
 $::form->{assortments}

CVar data is currently stored directly in $::form, e.g. $::form->{cvar_size}.

=item C<recalc_item_totals %params>

Helper function for calculating the total lastcost and sellprice for assemblies
or assortments according to their items, which are parsed from the current
$::form.

Is called whenever the qty of an item is changed or items are deleted.

Takes two params:

* part_type : 'assortment' or 'assembly' (mandatory)

* price_type: 'lastcost' or 'sellprice', default is 'sellprice'

Depending on the price_type the lastcost sum or sellprice sum is returned.

Doesn't work for recursive items.

=back

=head1 GET SET INITS

There are get_set_inits for

* assembly items

* assortment items

* makemodels

which parse $::form and automatically create an array of objects.

These inits are used during saving and each time a new element is added.

=over 4

=item C<init_makemodels>

Parses $::form->{makemodels}, creates an array of makemodel objects and stores them in
$self->part->makemodels, ready to be saved.

Used for saving parts and adding new makemodel rows.

=item C<parse_add_items_to_objects PART_TYPE>

Parses the resulting form from either the part-picker submit or the multi-item
submit, and creates an arrayref of assortment_item or assembly objects, that
can be rendered via C<render_assortment_items_to_html> or
C<render_assembly_items_to_html>.

Mandatory param: part_type: assortment or assembly (the resulting html will differ)
Optional param: position (used for numbering and listrow class)

=item C<render_assortment_items_to_html ITEM_OBJECTS>

Takes an array_ref of assortment_items, and generates tables rows ready for
adding to the assortment table.  Is used when a part is loaded, or whenever new
assortment items are added.

=item C<parse_form_makemodels>

Makemodels can't just be overwritten, because of the field "lastupdate", that
remembers when the lastcost for that vendor changed the last time.

So the original values are cloned and remembered, so we can compare if lastcost
was changed in $::form, and keep or update lastupdate.

lastcost isn't updated until the first time it was saved with a value, until
then it is empty.

Also a boolean "makemodel" needs to be written in parts, depending on whether
makemodel entries exist or not.

We still need init_makemodels for when we open the part for editing.

=back

=head1 TODO

=over 4

=item *

It should be possible to jump to the edit page in a specific tab

=item *

Support callbacks, e.g. creating a new part from within an order, and jumping
back to the order again afterwards.

=item *

Support units when adding assembly items or assortment items. Currently the
default unit of the item is always used.

=item *

Calculate sellprice and lastcost totals recursively, in case e.g. an assembly
consists of other assemblies.

=back

=head1 AUTHOR

G. Richardson E<lt>grichardson@kivitendo-premium.deE<gt>

=cut
