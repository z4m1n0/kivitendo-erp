# This file has been auto-generated. Do not modify it; it will be overwritten
# by rose_auto_create_model.pl automatically.
package SL::DB::Stock;

use strict;

use parent qw(SL::DB::Object);

__PACKAGE__->meta->table('stocks');

__PACKAGE__->meta->columns(
  id      => { type => 'integer', not_null => 1, sequence => 'id' },
  onhand  => { type => 'numeric', precision => 25, scale => 5 },
  part_id => { type => 'integer' },
);

__PACKAGE__->meta->primary_key_columns([ 'id' ]);

__PACKAGE__->meta->unique_keys([ 'part_id' ]);

__PACKAGE__->meta->foreign_keys(
  part => {
    class       => 'SL::DB::Part',
    key_columns => { part_id => 'id' },
    rel_type    => 'one to one',
  },
);

1;
;
