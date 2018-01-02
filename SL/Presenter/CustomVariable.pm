package SL::Presenter::CustomVariable;

use strict;

use SL::Presenter::Tag qw(hidden_tag checkbox_tag textarea_tag input_tag input_number_tag date_tag select_tag);
use SL::Presenter::EscapedText qw(escape);
use SL::Presenter::CustomerVendor qw(customer_picker vendor_picker);
use SL::Locale::String qw(t8);

use Exporter qw(import);
our @EXPORT_OK = qw(custom_variable_input_field custom_variable_label);

sub table_cell {
  $_[0]->value_as_text
}

sub input_field {
  my ($cvar, %params) = @_;

  $params{name_prefix} //= 'cvar_';
  $params{name_postfix} //= '';

  my $config = $cvar->config;
  my $name = $params{name} // join '', $params{name_prefix}, 'cvar_', $config->name, $params{name_postfix};

  if ($params{hidden}) {
    return hidden_tag($name, $cvar->value);
  }

  if (!$config->has_flag('editable')) {
    if ($params{hide_non_editable}) {
      return hidden_tag($name, $cvar->value);
    } else {
      return escape($cvar->value_as_text);
    }
  }

  if (!$cvar->is_valid) {
    if ($params{show_disabled_message}) {
      return escape(t8('Element disabled'));
    } else {
      return '';
    }
  }

  for my $type ($config->type) {
    return checkbox_tag($name, checked => $cvar->value)                           if $type eq 'bool';
    return textarea_tag($name, $cvar->value, $config->textarea_options)           if $type eq 'textfield';
    return date_tag($name, $cvar->value)                                          if $type eq 'date';
    return input_tag($name, $cvar->value)                                         if $type eq 'timestamp';
    return vendor_picker($name, $cvar->value)                                     if $type eq 'vendor';
    return customer_picker($name, $cvar->value)                                   if $type eq 'customer';
    return part_picker($name, $cvar->value)                                       if $type eq 'part';
    return select_tag($name, $config->processed_options, default => $cvar->value) if $type eq 'select';
    return input_number_tag($name, $cvar->value_as_text, $config->number_options) if $type eq 'number';
    return input_tag($name, $cvar->value, $config->text_options);
  }
}

sub input_with_label {
  &label . &input_field;
}

sub label {
  $_[0]->config->description
}

sub custom_variable_input_field { goto &input_field }
sub custom_variable_label       { goto &label }

1;

__END__

to do:

from oe/_sales_order.html - row2:

 <table class='row2-cvars-table'>
   <tr>
   [%- FOREACH row2 = row.ROW2 %]
     my $options = $row1->{render_options};
     my $show = ($options.var.flag_editable || !$options.hide_non_editable) && $options.valid && !$options.partsgroup_filtered) %]
     if ($row2.cvar && $show) {
       [%- IF row2.line_break %]
         </tr><tr>
       [%- END %]
     <th>
       [% row2.description %]
     </th>
     <td>
       [% PROCESS cvar_inputs cvar = row2.render_options %]
     </td>
     }
   [%- END %]
   </tr>
 </table>

 [%# process non editable cvars extra to not disturb the table layout (this will be hidden inputs) %]
 [%- FOREACH row2 = row.ROW2 %]
   [%- SET hide = (!row2.render_options.var.flag_editable && row2.render_options.hide_non_editable) %]
   [%- IF row2.cvar && hide %]
     [% PROCESS cvar_inputs cvar = row2.render_options %]
   [%- END %]
 [%- END %]

that in turn calls cvar_inputs which is included from amcvar/render_inputs_block and looks like render_input
