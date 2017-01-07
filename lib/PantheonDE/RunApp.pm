# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# This is part of pantheon-runapp
# Copyright (c) 2016 JEON Myoungjin <jeongoon@gmail.com>

package PantheonDE::RunApp;

use strict; use warnings;
use boolean;
use File::Spec;
use File::HomeDir;
use Time::HiRes   qw(CLOCK_REALTIME);

use parent 'Exporter';
use version 0.77; our $VERSION = version->declare( 'v0.2.1' );

# TODO
# umask for mkdir and any other file creation
# perldoc

our @EXPORT_OK = qw(getAppName          isDebugging     isVerbose
                    dmsg        leave   info
                    fs
                    loadConfig
                    getClockNow
                    prepareConfigDirectory
                    prepareCacheDirectory);

our %EXPORT_TAGS = ( 'auto' => [ qw(getAppName isDebugging isVerbose) ],
                     'msg'  => [ qw(dmsg leave info) ], );

sub msg_fmt_ {
    # xxx: slightly unreadable :-]
    die "not enough args" if scalar @_ < 2;
    my $label = $_[$#_-1];
    my $line  = $_[$#_];

    $label .= " "       if defined $label;
    $line   = ":$line"  if defined $line;

    "[${label}$$] $::AppName$line: "
}

sub info  (@); # like warning
sub leave (@); # like die
sub dmsg  (@); # like say STDERR, something

sub dbg_say (@) {
    my $label = shift;
    my ( undef, $file, $line ) =  caller(1);
    print msg_fmt_( $label, $line ), @_, $/;
}

my $die_sub  = sub (@) { dbg_say( 'FATAL', @_ ); exit 9 };
my $dmsg_sub = sub (@) { dbg_say( 'DEBUG', @_ ); };
my $info_sub = sub (@) { dbg_say( 'INFRM', @_ ); };

#$Exporter::Verbose = 1;

sub import {
    my $self = shift;

    $_->import for qw(strict warnings);

    my @exporter_args = $self->check_app_args( \@_ );

    # make Exporter::export_to_level can handle default tags ...
    # XXX something wrong with export_to_level(), so I need to put twice.
    unshift @exporter_args, ( ':auto' ) x 2;
    $self->Exporter::export_to_level( 1, @exporter_args );
}

sub check_app_args($) {
    my @a = @{pop@_};
    my @left;

    $::AppName = 'NoApp';
    $::Debug   = false;
    $::Verbose = false;

    while ( scalar @a ) {
        my $opt = shift @a;
        if    ( $opt eq '-AppName' ) {  $::AppName = shift @a; }
        elsif ( $opt eq '-Debug'   ) {  $::Debug   = getBoolean( shift @a );  }
        elsif ( $opt eq '-Verbose' ) {  $::Verbose = getBoolean( shift @a );  }
        elsif ( $opt eq '-Ewmh'    ) {  $::UseEwmh = getBoolean( shift @a );  }
        elsif ( $opt =~ /^-/       ) { die_sub->( "unknown option: $opt" );   }
        else                         { push @left, $opt;  }
    }

    if ( $::Debug ) {
        *dmsg = $dmsg_sub;      *leave = $die_sub;
    }
    else { # simpler message
        *dmsg = sub (@) {};     *leave = \&CORE::die;
    }

    if ( $::Verbose ) {
        *info = $::Debug
          ? $info_sub
          : sub (@) { say STDERR @_  };   }
    else            { *info = sub (@) {}; }

    $::UseEwmh and initEwmh();

    return @left;
}

sub getAppName  () { "$::AppName" }
sub isVerbose   () { boolean( $::Verbose ) }
sub isDebugging () { boolean( $::Debug   ) }

sub getBoolean  ($) {
    my $var = pop;
    defined $var or return false;

    # note: "$var" -> ensure the value for boolean object :-(
    if    ( "$var" =~ /1|y|yes|t|true/i )    { return true;  }
    elsif ( "$var" =~ /0|n|no|nil|false|/i ) { return false; }
    else {
        $info_sub->( "unknown boolean string: ".
                     "$var: assume that it ha sa false value" );
        return false;
    }

    $die_sub->( 'getBoolean(): this is a bug' );
}

# note:
sub hasEwmh() {
    boolean( scalar @::x_root_atoms > 0 );
}

sub initEwmh() {
    require X11::Protocol;
    $::X = X11::Protocol->new();
    # XXX: error handling ...
    @::x_root_atoms = $::x->ListProperties( $::X->root );

    $::EwmhCanActivateWindow =   ewmh_can_( '_NET_ACTIVE_WINDOW' );
    $::EwmhCanSetDesktop     = ( ewmh_can_( '_NET_WM_DESKTOP' )
                                 and
                                 ewmh_can_( '_NET_CURRENT_DESTKOP' ) );

    if ( hasEwmh ) {
        *EwmhSetDesktop = \&EwmhSetDesktop_;
        *EwmhActivateWindow = \&EwmhActivateWindow_;
    }
    else {
        *EwmhSetDestkop = sub ($) {
            EwmhNotSupported_( 'EwmhSetDestkop()' )     };
        *EwmhActivateWindow = sub ($) {
            EwmhNotSupported_( 'EwmhActivateWindow()' ) };
    }

    return true;
}

sub EwmhNotSupported ($) {
    leave "Could not $_[0]: EWMH ".
      ( $::UseEwmh and not hasEwmh ? 'NOT Supported' : 'NOT Used' );
}

sub EwmhSetDesktop_ {
    $::X->SendEvent( $::X->root, false,
                     $::X->pack_event_mask(  qw(SubstructureNotifyMask
                                               SubstructureRedirectMask) ),
                     getClientMessageEvent_( $::X->atom( '_NET_ACTIVE_WINDOW' ) ) );
}

# int xdo_set_current_desktop(const xdo_t *xdo, long desktop) {
#   /* XXX: This should support passing a screen number */
#   XEvent xev;
#   Window root;
#   int ret = 0;

#   root = RootWindow(xdo->xdpy, 0);

#   if (_xdo_ewmh_is_supported(xdo, "_NET_CURRENT_DESKTOP") == False) {
#     fprintf(stderr,
#             "Your windowmanager claims not to support _NET_CURRENT_DESKTOP, "
#             "so the attempt to change desktops was aborted.\n");
#     return XDO_ERROR;
#   }

#   memset(&xev, 0, sizeof(xev));
#   xev.type = ClientMessage;
#   xev.xclient.display = xdo->xdpy;
#   xev.xclient.window = root;
#   xev.xclient.message_type = XInternAtom(xdo->xdpy, "_NET_CURRENT_DESKTOP", 
#                                          False);
#   xev.xclient.format = 32;
#   xev.xclient.data.l[0] = desktop;
#   xev.xclient.data.l[1] = CurrentTime;

#   ret = XSendEvent(xdo->xdpy, root, False,
#                    SubstructureNotifyMask | SubstructureRedirectMask,
#                    &xev);

#   return _is_success("XSendEvent[EWMH:_NET_CURRENT_DESKTOP]", ret == 0, xdo);
# }

sub EwmhActivateWindow {
}

#sub getClientMessageEvent_($$) {
#    my ( $wid, $atom_name ) = $_[-2, -1];
#
#    my %event = { 'name' => 'ClientMessage',
#                  'root' => $::X->root,
#                  'window' => $::X->root,
#                  'time' => 'CurrentTime',
#                  'message_type' => $::X->atom( $atom_name ),
#                }

sub fs () { 'File::Spec' }

sub getClockNow () {
    Time::HiRes::clock_gettime( CLOCK_REALTIME );
}

sub prepareConfigDirectory ($) {  make_app_dir_( $_[-1], '.config' ) }
sub prepareCacheDirectory  ($) {  make_app_dir_( $_[-1], '.cache'  ) }

sub make_app_dir_( $$ ) {
    my $sub_name = pop;
    my $app_name = pop;

    my ( $volume, $directories, undef )
      = fs->splitpath( File::HomeDir->my_home, boolean( 'no file' ) );
    my @dirs = fs->splitdir( $directories );

    my $app_dir = fs->catdir( $volume, @dirs, $sub_name, $app_name );

    if ( ! -d $app_dir ) {
        info "$app_dir does not exists: making one";
        mkdir $app_dir or mkdir_fullpath( $volume, @dirs );
    }

    -d $app_dir ? $app_dir : undef;
}

sub loadConfig ($) {

}

sub mkdir_fullpath (@) {
    my ( $volume, @dirs ) = @_;
    for my $i ( 0 .. $#dirs ) {
        my $path = fs->catdir( $volume, @dirs[0..$i] );
        -e $path or mkdir $path or return false;
    }
    true;
}

sub ewmh_can_ ($) {
    for my $a ( @::x_root_atoms ) {
        return true if $_[-1] eq $a;
    }
    return false;
}

!!'^^';
