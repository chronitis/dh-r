#!/usr/bin/perl
# debhelper sequence for R package vignette building

use warnings;
use strict;
use Debian::Debhelper::Dh_Lib;

insert_before("dh_auto_install", "dh_vignette");

1;
