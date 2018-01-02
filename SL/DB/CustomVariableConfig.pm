# This file has been auto-generated only because it didn't exist.
# Feel free to modify it at will; it will not be overwritten automatically.

package SL::DB::CustomVariableConfig;

use strict;

use List::MoreUtils qw(any);

use SL::DB::MetaSetup::CustomVariableConfig;
use SL::DB::Manager::CustomVariableConfig;
use SL::DB::Helper::ActsAsList;

__PACKAGE__->meta->add_relationship(
  partsgroups  => {
    type       => 'many to many',
    map_class  => 'SL::DB::CustomVariableConfigPartsgroup',
  },
);

__PACKAGE__->meta->initialize;

__PACKAGE__->configure_acts_as_list(group_by => [qw(module)]);

sub validate {
  my ($self) = @_;

  my @errors;
  push @errors, $::locale->text('The name is missing.')        if !$self->name;
  push @errors, $::locale->text('The description is missing.') if !$self->description;
  push @errors, $::locale->text('The type is missing.')        if !$self->type;
  push @errors, $::locale->text('The option field is empty.')  if (($self->type || '') eq 'select') && !$self->options;

  return @errors;
}

use constant OPTION_DEFAULTS =>
  {
    MAXLENGTH => 75,
    WIDTH => 30,
    HEIGHT => 5,
  };

sub processed_options {
  my ($self) = @_;

  return $self->{processed_options_cache} if $self->{processed_options_cache};

  my $ops = $self->options;
  my $ret;

  if ( $self->type eq 'select' ) {
    my @op_array = split('##', $ops);
    $ret = \@op_array;
  }
  else {
    $ret = {%{$self->OPTION_DEFAULTS}};
    while ( $ops =~ /\s*([^=\s]+)\s*=\s*([^\s]*)(?:\s*|$)/g ) {
      $ret->{$1} = $2;
    }
  }

  $self->{processed_options_cache} = $ret;

  return $ret;
}

sub processed_flags {
  my ($self) = @_;

  return $self->{processed_flags_cache} if $self->{processed_flags_cache};

  my $flags = $self->flags;
  my $ret = {};

  foreach my $flag (split m/:/, $flags) {
    if ( $flag =~ m/(.*?)=(.*)/ ) {
      $ret->{$1} = $2;
    } else {
      $ret->{$flag} = 1;
    }
  }

  $self->{processed_flags_cache} = $ret;

  return $ret;
}

sub has_flag {
  $_[0]->processed_flags->{$_[1]};
}

sub type_dependent_default_value {
  my ($self) = @_;

  return $self->default_value if $self->type ne 'select';
  return (any { $_ eq $self->default_value } @{ $self->processed_options }) ? $self->default_value : $self->processed_options->[0];
}

sub textarea_options {
  my $options = $_[0]->processed_options;

  cols => $options->{WIDTH},
  rows => $options->{HEIGHT}
}

sub text_options {
  maxlength => $_[0]->processed_options->{MAXLENGTH}
}

sub number_options {
  precision => $_[0]->processed_options->{PRECISION}
}

sub value_col {
  my ($self) = @_;

  my $type = $self->type;

  return {
    bool      => 'bool_value',
    timestamp => 'timestamp_value',
    date      => 'timestamp_value',
    number    => 'number_value',
    integer   => 'number_value',
    customer  => 'number_value',
    vendor    => 'number_value',
    part      => 'number_value',
    text      => 'text_value',
    textfield => 'text_value',
    select    => 'text_value'
  }->{$type};
}

1;
