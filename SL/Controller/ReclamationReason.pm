# TODO(Tamino): check_auth
package SL::Controller::ReclamationReason;

use strict;

use parent qw(SL::Controller::Base);

use SL::DB::ReclamationReason;
use SL::Helper::Flash;
use SL::Locale::String;
use List::MoreUtils qw(any);
use SL::CVar;

use Rose::Object::MakeMethods::Generic (
  scalar                  => [ qw(reclamation_reason) ],
  'scalar --get_set_init' => [ qw(reclamation_reason) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('load_reclamation_reason', only => [ qw(edit delete) ]);

sub check_auth {
  $::auth->assert('config');
}

#
# actions
#

sub action_list {
  my ($self, %params) = @_;

  $self->setup_list_action_bar;
  $self->render(
    'reclamation_reason/list',
    title => $::locale->text('Reclamation Reasons'),
    RECLAMATION_REASONS => SL::DB::Manager::ReclamationReason->get_all_sorted(),
  );
}

sub action_sort_list {
  my ($self, %params) = @_;

  $self->setup_sort_list_action_bar;
  $self->render(
    'reclamation_reason/sort_list',
    title => $::locale->text('Reclamation Reasons'),
    RECLAMATION_REASONS => SL::DB::Manager::ReclamationReason->get_all_sorted(),
  );
}

sub action_new {
  my ($self) = @_;

  $self->reclamation_reason(SL::DB::ReclamationReason->new());
  $self->show_form(title => t8('Add Reclamation Reason'));
}

sub action_edit {
  my ($self) = @_;

  $self->show_form(
    title       => t8('Edit reclamation_reason'),
  );
}

sub action_save {
  my ($self) = @_;

  if ($::form->{id}) {
    $self->load_reclamation_reason();
  }

  $self->create_or_save;
}

sub action_delete {
  my ($self) = @_;

  if (!$self->reclamation_reason->db->with_transaction(sub {
    $self->reclamation_reason->delete();
    flash_later('info',  $::locale->text('The Reclamation Reason has been deleted.'));

    1;
  })) {
    flash_later('error', $::locale->text('The Reclamation Reason is in use and cannot be deleted.'))
  };

  $self->redirect_to(action => 'list');
}

#
# ajax actions
#

sub action_reorder {
  my ($self) = @_;

  SL::DB::ReclamationReason->reorder_list(@{ $::form->{reclamation_reason_id} || [] });

  $self->render(\'', { type => 'json' });
}

#
# action bars
#

sub setup_form_action_bar {
  my ($self) = @_;

  my $is_new = !$self->reclamation_reason->id;

  for my $bar ($::request->layout->get('actionbar')) {
    $bar->add(
      action => [
        t8($is_new ? 'Create' : 'Save'),
        submit    => [ '#form', { action => 'ReclamationReason/save' } ],
        checks    => [ 'kivi.validate_form' ],
        accesskey => 'enter',
      ],
      action => [
        t8('Delete'),
        submit   => [ '#form', { action => 'ReclamationReason/delete' } ],
        confirm  => t8('Do you really want to delete this Reclamation Reason?'),
        only_if  => !$is_new,
      ],
      link => [
        t8('Abort'),
        link => $self->url_for(action => 'list'),
      ],
    );
  }
  $::request->layout->add_javascripts('kivi.Validator.js');
}

sub setup_list_action_bar {
  my ($self) = @_;

  for my $bar ($::request->layout->get('actionbar')) {
    $bar->add(
      link => [
        t8('Add'),
        link => $self->url_for(action => 'new'),
      ],
      link => [
        t8('Sort'),
        link => $self->url_for(action => 'sort_list'),
      ],
    );
  }
}

sub setup_sort_list_action_bar {
  my ($self) = @_;

  for my $bar ($::request->layout->get('actionbar')) {
    $bar->add(
      link => [
        t8('Add'),
        link => $self->url_for(action => 'new'),
      ],
      link => [
        t8('List'),
        link => $self->url_for(action => 'list'),
      ],
    );
  }
}

#
# helpers
#

sub create_or_save {
  my ($self) = @_;

  unless ($self->reclamation_reason) {
    $self->reclamation_reason(SL::DB::ReclamationReason->new());
  }

  my $is_new = !$self->reclamation_reason->id;

  my $params = delete($::form->{reclamation_reason}) || { };
  delete $params->{id};

  my @errors;

  my $db = $self->reclamation_reason->db;
  if (!$db->with_transaction(sub {

    # assign attributes and validate
    $self->reclamation_reason->assign_attributes( %{$params} ) ;

    push(@errors, $self->reclamation_reason->validate); # check data before DB error

    if (@errors) {
      die @errors . "\n";
    };
    $self->reclamation_reason->save;
    1;
  })) {
    die @errors ? join("\n", @errors) . "\n" : $db->error . "\n";
  }

  flash_later('info', $is_new ? t8('The Reclamation Reason has been created.') : t8('The Reclamation Reason has been saved.'));
  $self->redirect_to(action => 'list');
}

sub show_form {
  my ($self, %params) = @_;

  $self->setup_form_action_bar;
  $self->render(
    'reclamation_reason/form',
    %params,
  );
}

sub load_reclamation_reason {
  my ($self) = @_;

  $self->reclamation_reason(SL::DB::ReclamationReason->new(id => $::form->{id})->load);
}

1;
