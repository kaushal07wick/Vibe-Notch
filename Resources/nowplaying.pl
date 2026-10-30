use DynaLoader;
my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
my $s = DynaLoader::dl_find_symbol($l, $ARGV[1]) or die DynaLoader::dl_error();
DynaLoader::dl_install_xsub("main::vn", $s); main::vn();
