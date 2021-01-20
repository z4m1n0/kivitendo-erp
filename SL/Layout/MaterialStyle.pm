package SL::Layout::MaterialStyle;

use strict;
use parent qw(SL::Layout::Base);

sub use_stylesheet {
  "https://cdnjs.cloudflare.com/ajax/libs/materialize/1.0.0/css/materialize.min.css",
  "https://fonts.googleapis.com/icon?family=Material+Icons";
}

sub use_javascript {
  "https://cdnjs.cloudflare.com/ajax/libs/materialize/1.0.0/js/materialize.min.js";
}

sub javascripts_inline {
<<'EOL';
  document.addEventListener('DOMContentLoaded', function() {
    var elems = document.querySelectorAll('select');
    var instances = M.FormSelect.init(elems);
  });
EOL
}

sub get_stylesheet_for_user {
  # overwrite kivitendo fallback
  'css/material';
}

1;
