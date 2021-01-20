package SL::Layout::MaterialMenu;

use strict;
use parent qw(SL::Layout::Base);
use SL::Menu;

sub init_menu {
  SL::Menu->new('mobile');
}

sub javascripts_inline {
<<'EOL';
  document.addEventListener('DOMContentLoaded', function() {
    var elems = document.querySelectorAll('.sidenav');
    var instances = M.Sidenav.init(elems);
  });
EOL
}

sub pre_content {
  $_[0]->presenter->render('menu/material', menu => $_[0]->menu);
}

1;
