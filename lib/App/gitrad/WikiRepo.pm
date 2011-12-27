package App::gitrad::WikiRepo;
use Moose;
use methods-invoker;
use App::gitrad qw/$App/;
use Git::Repository;
use IO::All;
use DirHandle;
use File::Temp;

has 'git_dir' => (is => 'ro', isa => 'Str', required => 1);

has '_git' => (is => 'ro', isa => 'Object', lazy_build => 1, handles => [qw/work_tree/]);

method _build__git {
    Git::Repository->new(git_dir => $->git_dir);
}


method get_homepage {
    return 'Home';
}

method get_page ($page_name) {
    return $->_find_in_worktree($page_name, sub { io(shift)->slurp })
        || "No such page.";
}

method edit_page (%opts) {
    my $page_name = $opts{page};
    my $page_file = $->_get_filename_for_page($page_name);
    my $editor   = $ENV{EDITOR} || '/usr/bin/vim';
    system( $editor, $page_file );
}

method _get_filename_for_page ($page_name) {
    return $->_find_in_worktree( $page_name, sub { shift } )
      || $->work_tree . '/' . $->canonicalize_page_name($page_name) . '.wiki';
}

method _find_in_worktree ($match, $cb) {
    unless (ref($match)) {
        $match = $->canonicalize_page_name($match);
        $match = qr#\Q$match\E\.(\w+)$#i;
    }
    my $d = DirHandle->new($->work_tree);
    while (defined($_ = $d->read)) {
        next if m/^\./;
        next unless $_ =~ $match;
        return $cb->($->work_tree . '/' . $_);
    }
    return undef;
}

method canonicalize_page_name ($name) {
    $name =~ s#\s+#_#g;
    $name;
}



1;
