package App::gitrad;
use Moose;
use Curses::UI;
use Carp qw/croak/;
use File::Path qw/mkpath/;
use methods-invoker;
use Git::Repository;
use App::gitrad::WikiRepo;
use base 'Exporter';
our @EXPORT_OK = qw/$App/;

our $VERSION = '0.70';

=head1 NAME

App::gitrad - efficient wiki browsing and editing for git repos

=head1 SYNOPSIS

  my $app = App::gitrad->new(dir => $git_wiki_dir);
  $app->run;

=cut

our $App;

has 'git_dir'  => ( is => 'ro', isa => 'Str', required   => 1 );
has 'save_dir' => ( is => 'ro', isa => 'Str', lazy_build => 1 );
has 'git'      => ( is => 'ro', isa => 'Object', lazy_build => 1 );
has 'cui'      => ( is => 'ro', isa => 'Object', lazy_build => 1 );
has 'win'      => ( is => 'ro', isa => 'Object', lazy_build => 1 );
has 'history' =>
  ( is => 'rw', isa => 'ArrayRef[HashRef]', default => sub { [] } );

method BUILD {
    $App = $self;
}

method _build_win {
    my $win = $->cui->add('main', 'App::gitrad::Window');
    $->cui->leave_curses;
    return $win;
}

method _build_cui {
    return Curses::UI->new( -color_support => 1 );
}

method _build_save_dir {
    my $dir = "$ENV{HOME}/gitrad";
    unless (-d $dir) {
        mkpath $dir or die "Can't mkpath $dir: $!";
    }
    return $dir;
}

method _build_git {
    my $repo = App::gitrad::WikiRepo->new(git_dir => $->git_dir);
}

sub run {
    my $self = shift;

    my $quitter = sub { exit };
    $self->cui->set_binding( $quitter, "\cq");
    $self->cui->set_binding( $quitter, "\cc");
    $self->win->{viewer}->set_binding( $quitter, 'q');

    $self->cui->reset_curses;
    $self->cui->mainloop;
}

sub set_page {
    my $self = shift;
    my $page = shift;
    my $no_history = shift;

    my $pb = $self->win->{page_box};

    unless ($no_history) {
        push @{ $self->{history} }, {
            page => $pb->text,
            pos  => $self->win->{viewer}{-pos},
        };
    }
    unless (defined $page) {
        $page = $self->git->get_homepage;
        $page = $self->git->get_homepage;
    }
    $pb->text($page);
    $self->load_page;
}

sub set_last_tagged_page {
    my $self = shift;
    my $tag  = shift;

    my @pages = $self->git->get_taggedpages($tag);
    $self->set_page(shift @pages);
}

sub go_back {
    my $self = shift;
    my $prev = pop @{ $self->{history} };
    if ($prev) {
        $self->set_page($prev->{page}, 1);
        $self->win->{viewer}{-pos} = $prev->{pos};
    }
}

sub get_page {
    return $App->win->{page_box}->text;
}

sub load_page {
    my $self = shift;
    my $current_page = $self->win->{page_box}->text;

    if (! $current_page) {
        $self->cui->status('Fetching list of pages ...');
        my @pages = $self->git->get_pages;
        $self->cui->nostatus;
        $App->win->listbox(
            -title => 'Choose a page',
            -values => \@pages,
            change_cb => sub {
                my $page = shift;
                $App->set_page($page) if $page;
            },
        );
        return;
    }

    $self->cui->status("Loading page $current_page ...");
    my $page_text = $self->git->get_page($current_page);
    $page_text = $self->_render_wikitext_wafls($page_text);
    $self->cui->nostatus;
    $self->win->{viewer}->text($page_text);
    $self->win->{viewer}->cursor_to_home;
}

sub _render_wikitext_wafls {
    my $self = shift;
    my $text = shift;

    if ($text =~ m/{st_(?:iteration|project)stories: <([^>]+)>}/) {
        my $tag = $1;
        my $replace_text = "Stories for tag: '$tag':\n";
        my @pages = $self->git->get_taggedpages($tag);
    
        $replace_text .= join("\n", map {"* [$_]"} @pages);
        $replace_text .= "\n";
        $text =~ s/{st_(?:iteration|project)stories: <[^>]+>}/$replace_text/;
    }

    return $text;
}


1;
