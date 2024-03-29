package App::gitrad::Window;
use strict;
use warnings;
use base 'Curses::UI::Window';
use Curses qw/KEY_ENTER/;
use App::gitrad qw/$App/;
use Socialtext::Resting;
use App::gitrad::Editor;
use JSON;
use Data::Dumper;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->_create_ui_widgets;

    my ($v, $p, $w, $t) = map { $self->{$_} } 
                          qw/viewer page_box tag_box/;
    $v->focus;
    $v->set_binding( \&choose_frontlink,         'g' );
    $v->set_binding( \&choose_backlink,          'B' );
    $v->set_binding( \&show_help,                '?' );
    $v->set_binding( \&recently_changed,         'r' );
    $v->set_binding( \&show_uri,                 'u' );
    $v->set_binding( \&show_includes,            'i' );
    $v->set_binding( \&clone_page,               'c' );
    $v->set_binding( \&clone_page_from_template, 'C' );
    $v->set_binding( \&show_metadata,            'm' );
    $v->set_binding( \&add_pagetag,              'T' );
    $v->set_binding( \&new_blog_post,            'P' );
    $v->set_binding( \&change_server,            'S' );
    $v->set_binding( \&save_to_file,             'W' );
    $v->set_binding( \&search,                   's' );

    $v->set_binding( sub { editor() },                  'e' );
    $v->set_binding( sub { editor(pull_includes => 1) }, 'E' );
    $v->set_binding( sub { $v->focus },                 'v' );
    $v->set_binding( sub { $p->focus; $self->{cb}{page}->($p) },      'p' );
    $v->set_binding( sub { $t->focus; $self->{cb}{tag}->($t) },       't' );

    $v->set_binding( sub { $v->viewer_enter }, KEY_ENTER );
    $v->set_binding( sub { $App->go_back }, 'b' );

    # this n/N messes up search next/prev
    $v->set_binding( sub { $v->next_link },    'n' );
    $v->set_binding( sub { $v->prev_link },    'N' );

    $v->set_binding( sub { $v->cursor_down },  'j' );
    $v->set_binding( sub { $v->cursor_up },    'k' );
    $v->set_binding( sub { $v->cursor_right }, 'l' );
    $v->set_binding( sub { $v->cursor_left },  'h' );
    $v->set_binding( sub { $v->cursor_to_home }, '0' );
    $v->set_binding( sub { $v->cursor_to_end },  'G' );

    return $self;
}

sub show_help {
    $App->cui->dialog( 
        -fg => 'yellow',
        -bg => 'blue',
        -title => 'Help:',
        -message => <<EOT);
Basic Commands:
 j/k/h/l/arrow keys - move cursor
 n/N     - move to next/previous link
 ENTER   - jump to page [under cursor]
 space/- - page down/up
 b       - go back
 e       - open page for edit
 r       - choose from recently changed pages

Awesome Commands:
 0/G - move to beginning/end of page
 p   - set page
 t   - tagged pages
 s   - search
 g   - frontlinks
 B   - backlinks
 E   - open page for edit (--pull-includes)
 u   - show the uri for the current page
 i   - show included pages
 m   - show page metadata (tags, revision)
 T   - Tag page
 c   - clone this page
 C   - clone page from template
 P   - New blog post (read tags from current page)
 S   - Change REST server

Find:
 / - find forward
 ? - find backwards 
 (Bad: find n/N conflicts with next/prev link)

Ctrl-q / Ctrl-c / q - quit
EOT
}

sub add_pagetag {
    my $g = $App->git;
    $App->cui->status('Fetching page tags ...');
    my $page_name = $App->get_page;
    my @tags = $g->get_pagetags($page_name);
    $App->cui->nostatus;
    my $question = "Enter new tags, separate with commas, prefix with '-' to remove\n  ";
    if (@tags) {
        $question .= join(", ", @tags) . "\n";
    }
    my $newtags = $App->cui->question($question) || '';
    my @new_tags = split(/\s*,\s*/, $newtags);
    if (@new_tags) {
        $App->cui->status("Tagging $page_name ...");
        for my $t (@new_tags) {
            if ($t =~ s/^-//) {
                eval { $g->delete_pagetag($page_name, $t) };
            }
            else {
                $g->put_pagetag($page_name, $t);
            }
        }
        $App->cui->nostatus;
    }
}

sub show_metadata {
    my $g = $App->git;
    $App->cui->status('Fetching page metadata ...');
    my $page_name = $App->get_page;
    my $json_text = $g->get_page($page_name);
    my $page_data = jsonToObj($json_text);
    $App->cui->nostatus;
    $App->cui->dialog(
        -title => "$page_name metadata",
        -message => Dumper $page_data,
    );
}

sub new_blog_post {
    my $g = $App->git;

    (my $username = qx(id)) =~ s/^.+?\(([^)]+)\).+/$1/s;
    my @now = localtime;
    my $default_post = sprintf '%s, %4d-%02d-%02d', $username,
                               $now[5] + 1900, $now[4] + 1, $now[3];
    my $page_name = $App->cui->question(
        -question => 'Enter name of new blog post:',
        -answer   => $default_post,
    ) || '';
    return unless $page_name;

    $App->cui->status('Fetching tags ...');
    my @tags = _get_current_tags($App->get_page);
    $App->cui->nostatus;

    $App->set_page($page_name);
    editor( tags => @tags );
}

sub show_uri {
    my $g = $App->git;
    my $output = $g->run('remote', '-v');
    $App->cui->dialog( -title => "Current page:", -message => " $output" );
}

sub clone_page {
    my @args = @_; # obj, key, args
    my $template_page = $args[2] || $App->get_page;
    my $g = $App->git;
    my $template = $g->get_page($template_page);
    my $new_page = $App->cui->question("Title for new page:");
    if ($new_page) {
        $App->cui->status("Creating page ...");
        $g->put_page($new_page, $template);
        my @tags = _get_current_tags($template_page);
        $g->put_pagetags($new_page, \@tags);
        $App->cui->nostatus;

        $App->set_page($new_page);
    }
}

sub _get_current_tags {
    my $page = shift;
    return grep { $_ ne 'template' } $App->git->get_pagetags($page);
}

sub clone_page_from_template {
    my $tag = 'template';
    $App->cui->status('Fetching pages tagged $tag...');
    $App->{rester}->accept('text/plain');
    my @pages = $App->{rester}->get_taggedpages($tag);
    $App->cui->nostatus;
    $App->win->listbox(
        -title => 'Choose a template',
        -values => \@pages,
        change_cb => sub { clone_page(undef, undef, shift) },
    );
}

sub show_includes {
    my $viewer = $App->win->{viewer};
    $App->cui->status('Fetching included pages ...');
    my $page_text = $viewer->text;
    while($page_text =~ m/\{include:? \[(.+?)\]\}/g) {
        my $included_page = $1;
        my $included_text = $App->git->get_page($included_page);
        my $new_text = "-----Included Page----- [$included_page]\n"
                       . "$included_text\n"
                       . "-----End Include----- \n";
        $page_text =~ s/{include:? \[\Q$included_page\E\]}/$new_text/;
    }
    $viewer->text($page_text);
    $App->cui->nostatus;
}

sub recently_changed {
    $App->cui->status('Fetching recent changes ...');
    my @recent = ["TODO FIXME"];
    $App->cui->nostatus;
    $App->win->listbox(
        -title => 'Choose a page link',
        -values => \@recent,
        change_cb => sub {
            my $link = shift;
            $App->set_page($link) if $link;
        },
    );
}

sub choose_frontlink {
    choose_link('get_frontlinks', 'page link');
}

sub choose_backlink {
    choose_link('get_backlinks', 'backlink');
}

sub choose_link {
    my $method = shift;
    my $text = shift;
    my $arg = shift;
    my $page = $App->get_page;
    $App->cui->status("Fetching ${text}s");
    $App->{rester}->accept('text/plain');
    my @links = $App->{rester}->$method($page, $arg);
    $App->cui->nostatus;
    if (@links) {
        $App->win->listbox(
            -title => "Choose a $text",
            -values => \@links,
            change_cb => sub {
                my $link = shift;
                $App->set_page($link) if $link;
            },
        );
    }
    else {
        $App->cui->error("No ${text}s");
    }
}

sub editor {
    my %extra_args = @_;
    $App->cui->status('Editing page');
    $App->cui->leave_curses;
    my $tags = delete $extra_args{tags};

    $App->git->edit_page(page => $App->get_page);
    $App->cui->reset_curses;
    $App->load_page;
}

sub tag_change {
    my $tag = $App->win->{tag_box}->text;

    my $chose_tagged_page = sub {
        my $tag = shift;
        $App->cui->status('Fetching tagged pages ...');
        my @pages = $App->git->get_taggedpages($tag);
        $App->cui->nostatus;
        if (@pages == 0) {
            $App->cui->dialog("No pages tagged '$tag' found ...");
            return;
        }
        $App->win->listbox(
            -title => 'Choose a tagged page',
            -values => \@pages,
            change_cb => sub {
                my $page = shift;
                $App->set_page($page) if $page;
            },
        );
    };
    if ($tag) {
        $chose_tagged_page->($tag);
    }
    else {
        $App->cui->status('Fetching tags ...');
        my @tags = $App->git->get_tags;
        $App->cui->nostatus;
        $App->win->listbox(
            -title => 'Choose a tag:',
            -values => \@tags,
            change_cb => sub {
                my $tag = shift;
                $chose_tagged_page->($tag) if $tag;
            },
        );
    }
}

sub search {
    my $query = $App->cui->question( 
        -question => "Search"
    ) || return;

    $App->cui->status("Looking for pages matching your query");
    my @matches = $App->git->get_pages(query => $query);;
    $App->cui->nostatus;
    $App->win->listbox(
        -title => 'Choose a page link',
        -values => \@matches,
        change_cb => sub {
            my $link = shift;
            $App->set_page($link) if $link;
        },
    );
}

sub save_to_file {
    my $filename;
    eval {
        my $page_name = Socialtext::Resting::name_to_id($App->get_page);
        $filename = $App->save_dir . "/$page_name.wiki";

        open(my $fh, ">$filename") or die "Can't open $filename: $!";
        print $fh $App->win->{viewer}->text;
        close $fh or die "Couldn't write $filename: $!";
    };
    my $msg = $@ ? "Error: $@" : "Saved to $filename";
    $App->cui->dialog(
        -title => "Saved page to disk",
        -message => $msg,
    );
}

sub toggle_editable {
    my $w = shift;
    my $cb = shift;
    my $readonly = $w->{'-readonly'};

    my $new_text = $w->text;
    $new_text =~ s/^\s*(.+?)\s*$/$1/;
    $w->text($new_text);

    if ($readonly) {
        $w->{last_text} = $new_text;
        $w->cursor_to_home;
        $w->focus;
    }
    else {
        $App->win->{viewer}->focus;
    }

    $cb->() if $cb and !$readonly;

    if (! $readonly and $w->text =~ m/^\s*$/) {
        $w->text($w->{last_text}) if $w->{last_text};
    }

    $w->readonly(!$readonly);
    $w->set_binding( sub { toggle_editable($w, $cb) }, KEY_ENTER );
}

sub _create_ui_widgets {
    my $self = shift;
    my %widget_positions = (
        page_field => {
            -width => 45,
            -x     => 32,
        },
        tag_field => {
            -width => 15,
            -x     => 85,
        },
        help_label => {
            -x => 107,
        },
        page_viewer => {
            -y => 1,
        },
    );
    
    my $win_width = $self->width;
    if ($win_width < 110 and $win_width >= 80) {
        $widget_positions{tag_field} = {
            -width => 18,
            -x     => 1,
            -y     => 1,
            label_padding => 6,
        };
        $widget_positions{help_label} = {
            -x => 32,
            -y => 1,
        };
        $widget_positions{page_viewer}{-y} = 2;
    }

    #######################################
    # Create the Page label and field
    #######################################
    my $page_cb = sub { toggle_editable( shift, sub { $App->load_page } ) };
    $self->{cb}{page} = $page_cb;
    $self->{page_box} = $self->add_field('Page:', $page_cb,
        %{ $widget_positions{page_field} },
    );

    #######################################
    # Create the Tag label and field
    #######################################
    my $tag_cb = sub { toggle_editable( shift, \&tag_change ) };
    $self->{cb}{tag} = $tag_cb;
    $self->{tag_box} = $self->add_field('Tag:', $tag_cb,
        %{ $widget_positions{tag_field} },
    );

    $self->add(undef, 'Label',
        -bold => 1,
        -text => "Help: hit '?'",
        %{ $widget_positions{help_label} },
    );

    #######################################
    # Create the page Viewer
    #######################################
    $self->{viewer} = $self->add(
        'viewer', 'App::gitrad::PageViewer',
        -border => 1,
        %{ $widget_positions{page_viewer} },
    );
}

sub listbox {
    my $self = shift;
    $App->win->add('listbox', 'App::gitrad::Listbox', @_)->focus;
}

sub add_field {
    my $self = shift;
    my $desc = shift;
    my $cb = shift;
    my %args = @_;
    my $x = $args{-x} || 0;
    my $y = $args{-y} || 0;
    my $label_padding = $args{label_padding} || 0;

    $self->add(undef, 'Label',
        -bold => 1,
        -text => $desc,
        -x => $x,
        -y => $y,
    );
    $args{-x} = $x + length($desc) + 1 + $label_padding;
    my $w = $self->add(undef, 'TextEntry', 
        -singleline => 1,
        -sbborder => 1,
        -readonly => 1,
        %args,
    );
    $w->set_binding( sub { $cb->($w) }, KEY_ENTER );
    return $w;
}

1;
