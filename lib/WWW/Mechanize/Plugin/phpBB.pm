package WWW::Mechanize::Plugin::phpBB;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.01';

use Log::Log4perl qw(:easy);
use HTML::TreeBuilder;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(url version));
__PACKAGE__->version($VERSION);

###########################################
sub init {
###########################################
    my($class, @args) = @_;

    no strict 'refs';

    *{caller() . '::phpbb_login'} = \&login;
    *{caller() . '::phpbb_forums'} = \&forums;
    *{caller() . '::phpbb_forum_enter'} = \&forum_enter;
    *{caller() . '::phpbb_topics'} = \&topics;
}

###########################################
sub login {
###########################################
    my ($mech, $user, $password) = @_;

    if(!defined $user or !defined $password) {
        LOGDIE 'usage: ->login($user, $password)';
    }

    my $old_autocheck = $mech->{autocheck};
    $mech->{autocheck} = 1;

    DEBUG "Logging in as user '$user'";

    eval {
        DEBUG "Finding 'Login' link ";
        my $link = $mech->find_link(url_regex => qr/login\.php/);
        die "Cannot find login.php link" unless defined $link;

        my $url = $link->url();

        DEBUG "Following link $url";
        $mech->follow_link(url => $url);

        DEBUG "Submitting login credentials for user '$user'";
        $mech->submit_form(
            fields => {
                username => $user,
                password => $password,
            },
            button => "login",
        );

        $link = $mech->find_link(
            url_regex => qr/\Qlogin.php?logout=true\E/);
        die "Login failed (wrong credentials?)" unless defined $link;
    };

    $mech->{autocheck} = $old_autocheck;

    if($@) {
        ERROR "$@";
        return undef;
    }

    INFO "Logged in as user '$user'";
}

###########################################
sub forums {
###########################################
    my ($mech) = @_;

    DEBUG "Finding all forums";

    my $forums = $mech->find_all_links(
            url_regex => qr/viewforum\.php|forumdisplay.php/ );

    DEBUG "Found forums ", 
          join(", ", map { '"' . $_->text() . '"' } @$forums), ".";

    return $forums;
}

###########################################
sub forum_enter {
###########################################
    my ($mech, $rex) = @_;

    for my $forum (@{ forums($mech) }) {
        if($forum->text() =~ /$rex/) {
            INFO "Entering Forum ", $forum->text();
            $mech->get($forum->url());
            return 1;
        }
    }

    ERROR "Cannot find forum matching $rex";

    return undef;
}

###########################################
sub topics {
###########################################
    my ($mech) = @_;

    DEBUG "Scraping topics from ", $mech->uri();

        # Scrape the topics and their links from a forum page
    my $tree = HTML::TreeBuilder->new();

    $tree->parse($mech->content()) or 
        LOGDIE "Cannot parse forum HTML from ", $mech->uri();

    my @topics = $tree->look_down(
        _tag  =>  "span",
        class => "topictitle",
    );

    my $topics_seen = {};
    my $topics_all  = [];

    for my $topic (@topics) {
        my $a = $topic->content()->[0];
        my $count = $topic->parent()->right()->as_text();

        my $url = URI::URL->new($a->attr('href'), $mech->uri());

            # Throw away session ID
        my %form = $url->query_form();
        delete $form{sid};
        $url->query_form(%form);

        next if exists $topics_seen->{$form{t}};

        my $this_topic = { url   => $url->abs->as_string(),
                           text  => $a->as_text(),
                           count => $count,
                         };

        $topics_seen->{$form{t}}++;
        push @$topics_all, $this_topic;
    }

    $tree->delete();

    DEBUG "Found topics ", 
          join(", ", 
          map { '"' . $_->{text} . ' (' . $_->{count} . ')"' } @$topics_all), 
          ".";

    return $topics_all;
}

1;

__END__

=head1 NAME

WWW::Mechanize::Plugin::phpBB - Screen scraper for phpBB installations

=head1 SYNOPSIS

    use WWW::Mechanize::Pluggable;
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);

    my $mech = new WWW::Mechanize::Pluggable;

    $mech->get("http://some.forum.site.com/forum");
    $mech->phpbb_login("username", "password");

        # Get a list of forums
    my $forums = $mech->phpbb_forums();
    for my $forum (@$forums) {
        print "Forum:", $forum->text(), "\n";
    }

        # Enter a forum matched by a regex
    $mech->phpbb_forum_enter(qr(^The Forum Name$));

        # Return a list of topics
    my $topics = $mech->phpbb_topics();
    for my $topic (@$topics) {
        print "headline=$topic->{text} url=$topic->{url}\n";
    }

=head1 DESCRIPTION

This is a screen scraper for phpBB installations. It can log in to
a phpBB web interface, and pull forum and topics names.

It is implemented as a plugin to WWW::Mechanize, using Joe McMahon's 
WWW::Mechanize::Pluggable framework.

=over 4

=item $mech-E<gt>phpbb_login($user, $passwd)

Log into the phpBB web interface using the given credentials. It requires
that the C<$mech> object currently points to a phpBB page showing a "Login"
link.

Returns C<undef> if the login fails and fires a
Log4perl message at level ERROR.

=item my $forums = $mech-E<gt>phpbb_forums()

If the C<$mech> object points to a forum site's overview page listing
the forums, phpbb_forums will return a ref to an array of forums.
Every element of the array is a WWW::Mechanize::Link object and
therefore has the methods C<text()> and C<url> to show forum name
and the forum url:

        # Get a list of forums
    my $forums = $mech->phpbb_forums();
    for my $forum (@$forums) {
        print "Forum:", $forum->text(), " ", $forum->url(), "\n";
    }

=item $mech-E<gt>phpbb_forum_enter($regex)

If the C<$mech> object points to a forum site's overview page listing
the forums, C<phpbb_forum_enter> will have the WWW::Mechanize object
enter the first forum matching the specified regex:

        # Enter a forum matched by a regex
    $mech->phpbb_forum_enter(qr(^The Forum Name$));

Returns 1 on success and undef on failure.

=item my $topics = $mech-E<gt>phpbb_topics()

If the C<$mech> object points to a forum page listing the topics,
C<phpbb_topics> will scrape the topics off that page (which might
only be a fraction of the topics available for the given forum):

        # Return a list of topics
    my $topics = $mech->phpbb_topics();
    for my $topic (@$topics) {
        print "headline=$topic->{text} url=$topic->{url}\n";
    }

Every element of the array ref returned is a hashref, containing
values for the keys C<text> (topic headline), C<url> (url to the
first page showing this topic), C<count> (number of postings for this topic).

=back

=head1 AUTHOR

Mike Schilli, m@perlmeister.com

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Mike Schilli, m@perlmeister.com

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.

=cut
