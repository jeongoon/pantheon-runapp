# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# This is part of pantheon-runapp
# Copyright (c) 2016 JEON Myoungjin <jeongoon@gmail.com>

package eOS::RunApp;

use strict; use warnings;
use boolean;
use File::Spec;
use File::HomeDir;
use Time::HiRes   qw(CLOCK_REALTIME);
use Scalar::Util  qw(blessed);

use parent 'Exporter';
use version 0.77; our $VERSION = version->declare( 'v0.1' );

# TODO
# umask for mkdir and any other file creation

our @EXPORT_OK = qw(getAppName          isDebugging     isVerbose
                    dmsg        leave   info
                    fs
                    getClockNow
                    prepareConfigDirectory);

our %EXPORT_TAGS = ( 'auto' => [ qw(getAppName isDebugging isVerbose) ],
                     'msg'  => [ qw(dmsg leave info) ] );

sub msg_fmt_ {
    die "not enough args" if scalar @_ < 2;
    my $label = $_[$#_-1];
    my $line  = $_[$#_];

    $label = "$label " if defined $label;
    $line  = ":$line"  if defined $line;

    "[${label}$$] $::AppName$line: "
}

sub info  (@);
sub leave (@);
sub dmsg  (@);
sub dbg_say (@) {
    my $label = shift;
    my ( undef, $file, $line ) = caller(1);
    print msg_fmt_( $label, $line ), @_, $/;
}

my $die_sub  = sub (@) { dbg_say( 'FATAL', @_ ); };
my $dmsg_sub = sub (@) { dbg_say( 'DEBUG', @_ ); };
my $info_sub = sub (@) { dbg_say( 'INFO',  @_ ); };

#$Exporter::Verbose = 1;
sub import {
    my $self = shift;
    my $pkg  = caller;

    $_->import for qw(strict warnings);

    # make Exporter::export_to_level can handle default tags ...
    my @exporter_args = ( ":auto" );

    while ( scalar @_ ) {
        my $opt = shift;
        if    ( $opt eq '-AppName' ) {  $::AppName = shift; }
        elsif ( $opt eq '-Debug'   ) {  $::Debug   = getBoolean( shift ); }
        elsif ( $opt eq '-Verbose' ) {  $::Verbose = getBoolean( shift ); }
        elsif ( $opt =~ /^-/       ) { die "unknown option: $opt"; }
        else                         { push @exporter_args, $opt;  }
    }

    if ( $::Debug ) {
        # FIXME: use simpler output method
        #        with simpler file name and line number
        require Carp; Carp->import();
        $Carp::CarpLevel = 1;

        *dmsg = $dmsg_sub;      *leave = $die_sub;
    }
    else {
        *dmsg = sub (@) {};     *leave = \&CORE::die;
    }

    if ( $::Verbose ) {
        *info = $::Debug
          ? \&dmsg
          : sub (@) { say STDERR @_  };   }
    else            { *info = sub (@) {}; }

    Exporter::export_to_level( $self, 1, ":default", @exporter_args );
}

sub getAppName  () { "$::AppName" }
sub isVerbose   () { boolean( $::Verbose ) }
sub isDebugging () { boolean( $::Debug   ) }

sub getBoolean  ($) {
    my $var = pop;
    $var = "$var" if defined $var and blessed $var; # for boolean object :-(

    return false unless defined $var;
    if ( $var =~ /1|y|yes|t|true/i )       {   return true;  }
    elsif ( $var =~ /0|n|no|nil|false|/i ) {   return false; }
    else {
        # die ??
        warn "unknown boolean string: $var: assume that it ha sa false value";
        return false;
    }

    die 'getBoolean(): this is a bug';
}

sub fs () { 'File::Spec' }

sub getClockNow () {
    Time::HiRes::clock_gettime( CLOCK_REALTIME );
}

sub prepareConfigDirectory ($) {
    my $appname = pop;
    my ( $volume, $directories, undef )
      = fs->splitpath( File::HomeDir->my_home, boolean( 'no file' ) );
    my @dirs = fs->splitdir( $directories );

    my $config_dir = fs->catdir( $volume, @dirs, '.config', $appname );

    if ( ! -d $config_dir ) {
        info "$config_dir does not exists: making one";
        mkdir $config_dir or mkdir_fullpath( $volume, @dirs );
    }

    -d $config_dir ? $config_dir : undef;
}

sub mkdir_fullpath (@) {
    my ( $volume, @dirs ) = @_;
    for my $i ( 0 .. $#dirs ) {
        my $path = fs->catdir( $volume, @dirs[0..$i] );
        -e $path or mkdir $path or return false;
    }
    true;
}


!!'^^';
