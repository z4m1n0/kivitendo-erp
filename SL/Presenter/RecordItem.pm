package SL::Presenter::RecordItem;

use strict;

use List::UtilsBy qw(partition_by);
use SL::Presenter::CustomVariable qw(custom_variable_input_field custom_variable_label);
use SL::Presenter::Tag qw(html_tag);
use SL::Presenter::EscapedText qw(escape is_escaped);

use Exporter qw(import);
our @EXPORT_OK = qw();

sub cvar_inputs_as_block {
  my ($obj, %params) = @_;

  return '' unless $obj;

  $params{columns} //= $::myconfig{form_cvars_nr_cols} || 3;

  # all _valid_ of these have to be rendered, either hidden or openly.
  # if non-editable should be hidden, filter those out
  # partsgroup filtered are done by validity

  my $cvars        = $obj->cvars_by_config;
  my $hidden_cvars = [];

  if ($params{hide_non_editable}) {
    my %cvars_by_editable = partition_by { $_->config->has_flag('editable') * 1 } @$cvars;
    $cvars        = $cvars_by_editable{1};
    $hidden_cvars = $cvars_by_editable{0};
  }

  my $row_html = '';
  my $hidden = join '', map custom_variable_input_field($_, hidden => 1), @$hidden_cvars;

  for my $row (_tuples_of($params{columns} => @$cvars)) {
    $row_html .= html_tag('tr', join '', map {
      html_tag('th', custom_variable_label($_)),
      html_tag('td', custom_variable_input_field($_))
    } @$row)
  }

  $row_html .= html_tag('tr', html_tag('td', $hidden), style => 'display:hidden');

  $params{table} ? html_tag('table', $row_html, class => 'row2-cvars-table') : $row_html;
}

sub _tuples_of {
  my ($size, @array) = @_;

  die 'tuple size must be positive' unless defined $size && $size > 0;

  my $number_of_tuples = int(@array / $size) + !!(@array % $size);

  @array ? map [ splice @array, 0, $size ], 1 .. $number_of_tuples : ()
}

1;
