#!/usr/bin/perl -w
# WordPress Manager Script
# by Weston Ruter <weston@shepherd-interactive.com>
# Copyright 2010, Shepherd Interactive <http://shepherdinteractive.com/>
# 
# License: GPL 3.0 <http://www.gnu.org/licenses/gpl.html>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

use warnings;
use strict;
use open ':utf8';
use Getopt::Std;
use Text::Wrap;
our $VERSION = '0.6b';

my $help = <<HELP;
WordPress Manager Script, version $VERSION
  by Weston Ruter <weston\@shepherd-interactive.com>
Usage: perl wp-manage.pl <subcommand> [options] [args]
  Sets up WordPress installations with svn:externals, keeps version and plugins
  up to date with contents of config.json, facilitates database dumps and
  migrations between environments (due to the fact that URLs are hard-coded
  into in the database as as permalinks).

Examples:
  perl wp-manage.pl init
  perl wp-manage.pl init -c ../config.json
  perl wp-manage.pl update
  perl wp-manage.pl dumpdata development
  perl wp-manage.pl pushdata staging
  perl wp-manage.pl pushdata -f production

Suggestion: Checkout wp-manage.pl to a svn:externals directory and then in the
directory above store config.js and various shell scripts to invoke various
commands. A typical project root should look like this:
  /wp-manage/wp-manage.pl
  /config.json
  /dumpdev-pushstaging.sh
  /db/development.sql
  /db/staging.sql
  /db/production.sql
  /public/index.php
  /public/wp-config.php
  ...
  /public/wp-content/...
Where dumpdev-pushstaging.sh would contain:
  perl wp-manage/wp-manage.pl dumpdata development
  perl wp-manage/wp-manage.pl pushdata staging

HELP

# All of the possible subcommands
my %subcommands = (
	init      => {
		description => "Start a new WordPress install using configuration file."
	},
	dumpdata  => {
		description => "Dump the database from the specified environment into a
		                file {environment}.sql in the config db_dump_dir. Note
		                that the password is supplied to mysqldump as an
		                argument which is sent over the wire as cleartext.",
		arguments   => [
			{
				name => 'environment',
				optional => 1
			}
		]
	},
	pushdata  => {
		description => "Take the latest dump produced from the dumpdata
		                subcommand and push it to the supplied environment
		                after converting the HTTP host name from the source
		                dump to match the destination environment HTTP host
		                name. If the source_env is not provided, the
		                default_environment is assumed. Note that the password
		                is supplied to the mysql client as an argument which
		                is sent over the wire as cleartext.",
		arguments   => [
			{
				name => 'source_env',
				optional => 1
			},
			{
				name => 'dest_env',
				#optional => 1
			}
		]
	},
	help      => {
		description => "Display this screen."
	},
	update    => {
		description => "Updates the svn:externals definitions for the WP
		                version and plugins defined in config file and then
		                does svn up."
	},
);

# All of the valid options
my %options = (
	'c' => {
		value       => "configfile",
		default     => "./config.json",
		description => "The configuration file (defaults to ./config.json)"
	},
	'v' => {
		description => "Verbose mode"
	},
	'f' => {
		description => "Force the potentially destructive action to occur",
		subcommands => [qw( pushdata )]
	},
	'p' => {
		value       => "shellscript",
		description => "Post-hook shell script for dumpdata, and pre-hook for pushdata; SQL dump file path is passed as argument",
		subcommands => [qw( pushdata dumpdata )]
	}
);

# Get the invoked subcommand
my $subcommand = lc shift @ARGV;
die "First argument must be valid subcommand; run wp-manage.pl help\n" if $subcommand && not exists $subcommands{$subcommand};
$subcommand ||= 'help';

# Get the allowed option arguments for this subcommand
my $optstring = '';
foreach(keys %options){
	$optstring .= $_;
	$optstring .= ':' if exists $options{$_}->{value};
}

# Get the arguments
my %args;
getopts($optstring, \%args);


# Supply default argument option values
foreach my $switch (keys %options){
	if((not exists $args{$switch}) && (exists $options{$switch}->{default})){
		$args{$switch} = $options{$switch}->{default};
	}
}

# Detect illegal arguments
foreach my $switch (keys %args){
	if((exists $options{$switch}->{subcommands}) && !grep /$subcommand/, @{$options{$switch}->{subcommands}}){
		die "Illegal option '$switch' for subcommand '$subcommand'\n";
	}
}


# If no subcommand given, display help
if($subcommand eq 'help'){
	print $help;
	print "Available subcommands:\n";
	foreach my $subcommand (sort keys(%subcommands)){
		print "  $subcommand";
		my @switches;
		foreach my $switch (sort keys %options){
			next if exists $options{$switch}->{subcommands} && !grep /$subcommand/, @{$options{$switch}->{subcommands}};
			push @switches, "-$switch";
			push @switches, $options{$switch}->{value} if exists $options{$switch}->{value};
		}
		if($subcommand ne 'help'){
			print "[";
			print join " ", @switches;
			print "]  ";
		}
		if(exists $subcommands{$subcommand}->{arguments}){
			foreach my $argument (@{$subcommands{$subcommand}->{arguments}}){
				print(($argument->{optional} ? '[' . $argument->{name} . ']' : $argument->{name}) . " ");
			}
		}
		print "\n";
		my $desc = $subcommands{$subcommand}->{description};
		$desc =~ s{\n\s+}{ }g;
		print wrap("    ", "    ", $desc);
		print "\n\n";
	}
	
	print "All options:\n";
	foreach my $switch (sort keys(%options)){
		print "   -$switch";
		if(exists $options{$switch}->{value}){
			print " " . $options{$switch}->{value};
			if(exists $options{$switch}->{default}){
				print " (default: " . $options{$switch}->{default} . ")";
			}
		}
		print "\n";
		print wrap("     ", "     ", $options{$switch}->{description});
		print "\n";
		
	}
	exit;
}


# Load configuration file
my $configFile = $args{'c'}; #"./config.json"
use JSON;
-f $configFile or die "Config file does not exist $configFile\n";
open CONFIG, $configFile or die "Unable to read from $configFile\n";
my $config = decode_json(join '', <CONFIG>);
close CONFIG;

# Add config aliases
foreach my $env (values %{$config->{'environments'}}){
	$env->{'server_name'} = $env->{'http_host'} if (not exists $env->{'server_name'}) && exists $env->{'http_host'};
	$env->{'db_password'} = $env->{'db_pass'}   if (not exists $env->{'db_password'}) && exists $env->{'db_pass'};
}


#use Data::Dumper;
#print Dumper($config);
#my $environment = shift @ARGV || $config->{default_environment};
#print "\n##$environment##";
#exit;


die "Error: The current directory must be an SVN working copy.\n" if not -e '.svn';

my $svn_verbose_switch   .= exists $args{v} ? ' --verbose ' : '';
my $mysql_verbose_switch .= exists $args{v} ? ' --verbose ' : '';

use File::Basename;
sub in_array #http://www.go4expert.com/forums/showthread.php?t=8978
{
	my $search_for = shift;
	my %items = map {$_ => 1} @_; # create a hash out of the array values
	return exists $items{$search_for};
}


# Setup new installation
if($subcommand eq 'setup' || $subcommand eq 'install' || $subcommand eq 'init'){
	
	# Create directories and add them to repo
	system("svn $svn_verbose_switch mkdir " . ($config->{'db_dump_dir'} || 'db'));
	my $public_dir = ($config->{'public_dir'} || 'public');
	system("svn $svn_verbose_switch mkdir $public_dir");
	system("svn $svn_verbose_switch mkdir $public_dir/wp-content");
	system("svn $svn_verbose_switch mkdir $public_dir/wp-content/uploads");
	chmod(0777,      "$public_dir/wp-content/uploads");
	system("svn $svn_verbose_switch mkdir $public_dir/wp-content/cache");
	chmod(0777,      "$public_dir/wp-content/cache");
	system("svn $svn_verbose_switch mkdir $public_dir/wp-content/plugins");
	chmod(0777,      "$public_dir/wp-content/plugins");
	
	my($wp_repo_url, $wp_repo_rev) = split(/\?r=/, $config->{wp_repo});
	$wp_repo_rev ||= "HEAD";
	$wp_repo_url .= '/' if $wp_repo_url !~ m{/$}; #trailingslashit
	my $wp_repo_rev_arg = '';
	if($wp_repo_rev ne 'HEAD'){
		$wp_repo_rev_arg = "-r$wp_repo_rev";
	}
	
	# Grab the 
	system("svn export $svn_verbose_switch --force --non-recursive $wp_repo_rev_arg $wp_repo_url $public_dir");
	
	# Ignore files
	my @ignore = ();
	push @ignore, "wp-config-sample.php";
	push @ignore, "license.txt";
	push @ignore, "readme.html";
	open EXT, ">~temp.txt";
	print EXT join("\n", @ignore);
	close EXT;
	system("svn propset svn:ignore -F ~temp.txt $public_dir");
	
	# Add files
	chdir($public_dir);
	foreach(<*>){
		if(-f && !in_array($_, @ignore)){
			system("svn add $_");
		}
	}
	chdir('..');
	#system("svn add $public_dir");
	
	# Load the admin and includes directories
	use File::Path;
	
	my @externals = ();
	rmtree("$public_dir/wp-admin");
	push @externals, "wp-admin      $wp_repo_rev_arg   ${wp_repo_url}wp-admin";
	rmtree("$public_dir/wp-includes");
	push @externals, "wp-includes   $wp_repo_rev_arg   ${wp_repo_url}wp-includes";
	open EXT, ">~temp.txt";
	print EXT join("\n", @externals);
	close EXT;
	system("svn propset svn:externals -F ~temp.txt $public_dir");
	
	# Add plugins
	@externals = ();
	open EXT, ">~temp.txt";
	#foreach my $url (@{$config->{plugin_repos}}){
	while(my($pluginDir, $urlWithRepo) = each(%{$config->{plugin_repos}})){
		my($plugin_repo_url, $plugin_rev) = split(/\?r=/, $urlWithRepo);
		$plugin_rev ||= "HEAD";
		$plugin_repo_url .= '/' if $plugin_repo_url !~ m{/$}; #trailingslashit
		my $plugin_rev_arg = '';
		if($plugin_rev ne 'HEAD'){
			$plugin_rev_arg = " -r$plugin_rev ";
		}
		push @externals, "$pluginDir  $plugin_rev_arg  $plugin_repo_url";
	}
	print EXT join("\n", @externals);
	close EXT;
	system("svn propset svn:externals -F ~temp.txt $public_dir/wp-content/plugins");
	
	
	# Setup the wp-config.php file
	use LWP::Simple;
	my $authenticationUniqueKeys = get("http://api.wordpress.org/secret-key/1.1/");
	my $charset = $config->{db_charset} || 'utf8';
	my $table_prefix = exists $config->{db_table_prefix} ? $config->{db_table_prefix} : 'wp_';
	
	my $mySqlConstants = '';
	my $c;
	foreach my $env (keys %{$config->{'environments'}}){
		next if $env eq 'production';
		$c = $config->{'environments'}->{$env};
		
		$mySqlConstants .= $mySqlConstants ? "else if(" : "if(";
		$mySqlConstants .= '$_SERVER["HTTP_HOST"] == "' . $c->{server_name} . '"';
		$mySqlConstants .= "){\n";
		$mySqlConstants .= "\tdefine('DB_NAME', '" . $c->{'db_name'} . "');\n";
		$mySqlConstants .= "\tdefine('DB_USER', '" . $c->{'db_user'} . "');\n";
		$mySqlConstants .= "\tdefine('DB_PASSWORD', '" . ($c->{'db_password'}) . "');\n";
		$mySqlConstants .= "\tdefine('DB_HOST', '" . ($c->{'db_host'} || '127.0.0.1') . "');\n";
		$mySqlConstants .= "\tdefine('WP_DEBUG', " . ($c->{'debug'}) . ");\n" if $c->{'debug'};
		$mySqlConstants .= "}\n";
	}
	
	if(exists $config->{'environments'}->{'production'}){
		$c = $config->{'environments'}->{'production'};
		$mySqlConstants .= "else {\n";
		$mySqlConstants .= "\tdefine('DB_NAME', '" . $c->{'db_name'} . "');\n";
		$mySqlConstants .= "\tdefine('DB_USER', '" . $c->{'db_user'} . "');\n";
		$mySqlConstants .= "\tdefine('DB_PASSWORD', '" . ($c->{'db_password'}) . "');\n";
		$mySqlConstants .= "\tdefine('DB_HOST', '" . ($c->{'db_host'} || '127.0.0.1') . "');\n";
		$mySqlConstants .= "\tdefine('WP_DEBUG', " . ($c->{'debug'}) . ");\n" if $c->{'debug'};
		$mySqlConstants .= "}\n";
	}
	
	open WPCONFIG, ">$public_dir/wp-config.php";
	print WPCONFIG <<WPCONFIGFILE;
<?php
/** 
 * The base configurations of the WordPress.
 *
 * This file has the following configurations: MySQL settings, Table Prefix,
 * Secret Keys, WordPress Language, and ABSPATH. You can find more information by
 * visiting {\@link http://codex.wordpress.org/Editing_wp-config.php Editing
 * wp-config.php} Codex page. You can get the MySQL settings from your web host.
 *
 * This file is used by the wp-config.php creation script during the
 * installation. You don't have to use the web site, you can just copy this file
 * to "wp-config.php" and fill in the values.
 *
 * \@package WordPress
 */

// ** MySQL settings ** //
$mySqlConstants

define('DB_CHARSET', '$charset');
define('DB_COLLATE', '');

/**#\@+
 * Authentication Unique Keys.
 */
$authenticationUniqueKeys
/**#\@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each a unique
 * prefix. Only numbers, letters, and underscores please!
 */
\$table_prefix  = '$table_prefix';

/**
 * WordPress Localized Language, defaults to English.
 *
 * Change this to localize WordPress.  A corresponding MO file for the chosen
 * language must be installed to wp-content/languages. For example, install
 * de.mo to wp-content/languages and set WPLANG to 'de' to enable German
 * language support.
 */
define ('WPLANG', '$config->{lang}');

/* That's all, stop editing! Happy blogging. */

/** WordPress absolute path to the Wordpress directory. */
if ( !defined('ABSPATH') )
	define('ABSPATH', dirname(__FILE__) . '/');

/** Sets up WordPress vars and included files. */
require_once(ABSPATH . 'wp-settings.php');

WPCONFIGFILE
	close WPCONFIG;
	
	system("svn add $public_dir/wp-config.php");
	
	# Create databases development only (staging and production must be setup manually)
	if(exists $config->{environments}->{$config->{default_environment}}){
		$c = $config->{environments}->{$config->{default_environment}};
		open SQL, ">~temp.txt";
		print SQL "CREATE DATABASE `$c->{db_name}`"; #IF NOT EXISTS
		print SQL " DEFAULT CHARACTER SET $config->{db_charset}" if $config->{db_charset};
		print SQL ";";
		close SQL;
		system("mysql $mysql_verbose_switch -u $c->{db_user} --password=$c->{db_password} < ~temp.txt");
	}
	
	#foreach my $env (keys %{$config->{'environments'}}){
	#	my $c = $config->{'environments'}->{$env};
	#	#if($c->{db_user})
	#	
	#	system("mysql $mysql_verbose_switch -u $c->{db_user} --password=$c->{db_password}");
	#}
	
	# Add a theme
	system("svn mkdir $svn_verbose_switch $public_dir/wp-content/themes");
	system("svn mkdir $svn_verbose_switch $public_dir/wp-content/themes/" . $config->{theme_slug});
	open CSS, ">$public_dir/wp-content/themes/" . $config->{theme_slug} . "/style.css";
	print CSS "/*
Theme Name: $config->{site_name}
Author: $config->{theme_author}
*/";
	close CSS;
	system("svn add $public_dir/wp-content/themes/" . $config->{theme_slug} . "/style.css");
	open PHP, ">$public_dir/wp-content/themes/" . $config->{theme_slug} . "/index.php";
	print PHP "Theme is empty";
	close PHP;
	system("svn add $public_dir/wp-content/themes/" . $config->{theme_slug} . "/index.php");
	system("svn up $svn_verbose_switch");
	
	#Week Starts On: Sunday
	# 
	#Ensure that uploads_dir is set to wp-content/uploads
	#Ensure that uploads are not uploaded into categories
	#Turn on Permalinks
	#Set admin email and site name
	#Set theme
	
	unlink('~temp.txt');
	exit;
}


# Updates the WP version to the version located at config.wp_repo and does svn up
if($subcommand eq 'update' || $subcommand eq 'up'){
	my $public_dir = ($config->{'public_dir'} || 'public');
	
	# Update the WP Install
	my($wp_repo_url, $wp_repo_rev) = split(/\?r=/, $config->{wp_repo});
	$wp_repo_rev ||= "HEAD";
	$wp_repo_url .= '/' if $wp_repo_url !~ m{/$}; #trailingslashit
	my $wp_repo_rev_arg = '';
	if($wp_repo_rev ne 'HEAD'){
		$wp_repo_rev_arg = "-r$wp_repo_rev";
	}
	system("svn export $svn_verbose_switch --force --non-recursive $wp_repo_rev_arg $wp_repo_url $public_dir");
	
	my $externals = `svn propget svn:externals $public_dir`;
	$externals =~ s{(-r\s*\d+\s*)?http://(core\.svn\.wordpress\.org|svn\.automattic\.com)/.+?/(?=wp-admin|wp-includes)}
	                 {$wp_repo_rev_arg   $wp_repo_url}g;
	$externals =~ s{\s+$}{\n}s; #remove trailing slashes
	
	open TEMP, ">~propset.txt";
	print TEMP $externals;
	close TEMP;
	system("svn propset svn:externals -F ~propset.txt $public_dir ");
	unlink('~propset.txt');
	
	
	# Update the plugins
	my @externals = ();
	open EXT, ">~temp.txt";
	#foreach my $url (@{$config->{plugin_repos}}){
	while(my($pluginDir, $urlWithRepo) = each(%{$config->{plugin_repos}})){
		my($plugin_repo_url, $plugin_rev) = split(/\?r=/, $urlWithRepo);
		$plugin_rev ||= "HEAD";
		$plugin_repo_url .= '/' if $plugin_repo_url !~ m{/$}; #trailingslashit
		my $plugin_rev_arg = '';
		if($plugin_rev ne 'HEAD'){
			$plugin_rev_arg = " -r$plugin_rev ";
		}
		push @externals, "$pluginDir  $plugin_rev_arg  $plugin_repo_url";
	}
	print EXT join("\n", @externals);
	close EXT;
	system("svn propset svn:externals -F ~temp.txt $public_dir/wp-content/plugins");
	system("svn up $svn_verbose_switch");
	
	#print "Now do svn up and svn commit to have your changes enacted.\n";
	unlink('~temp.txt');
	exit;
}



# Take the data from an environment and dump it out so it can be imported into each other environment
if($subcommand eq 'dumpdata' || $subcommand eq 'datadump'){
	#Get the destination environment
	my $environment = shift @ARGV || $config->{default_environment};
	die "Unrecognized environment '$environment'\n" if not exists $config->{'environments'}->{$environment};
	my $c = $config->{'environments'}->{$environment};
	
	#The servers other than primary are the destinations
	my @environments = keys(%{$config->{environments}});
	my @destinations = grep !/^$environment$/i, @environments;
	
	#Dump the source database
	my $db_dump_dir = ($config->{'db_dump_dir'} || 'db');
	my @options = (
		$mysql_verbose_switch,
		'--host "' . ($c->{db_host} || $c->{server_name}) . '"',
		'--user "' . $c->{db_user} . '"',
		'--password="' . $c->{db_password} . '"',
		'--quick',
		'--extended-insert=FALSE',
		'--complete-insert',
		'--skip-comments',
		'--no-create-db',
		'"' . $c->{db_name} . '"'
	);
	
	if(exists $config->{'db_tables'} && scalar @{$config->{'db_tables'}}){
		push @options, '"' . join('" "', @{$config->{'db_tables'}}) . '"';
	}
	system('mysqldump ' . join(' ', @options) . " > $db_dump_dir/$environment.sql");
	system("$args{p} $db_dump_dir/$environment.sql") if exists $args{p} && $args{p};
	exit;
}

# Take the data from an environment and dump it out so it can be imported into each other environment
if($subcommand eq 'pushdata' || $subcommand eq 'datapush'){
	
	my $db_dump_dir = ($config->{'db_dump_dir'} || 'db');
	
	#Get the destination environment
	my($source_env, $dest_env);
	if(@ARGV == 1){
		$source_env = $config->{default_environment};
		$dest_env = shift @ARGV;
	}
	elsif(@ARGV > 1) {
		$source_env = shift @ARGV;
		$dest_env = shift @ARGV;
	}
	
	die "Source environment (source_env) not provided\n" if !$source_env;
	die "Unrecognized environment '$source_env'\n" if not exists $config->{'environments'}->{$source_env};
	die "Destination environment (dest_env) not provided\n" if !$dest_env;
	die "Unrecognized environment '$dest_env'\n" if not exists $config->{'environments'}->{$dest_env};
	
	my $isForce = exists $args{f};
	my $cSource = $config->{'environments'}->{$source_env};
	my $cDest = $config->{'environments'}->{$dest_env};
	
	die "Error: In order to push to $dest_env, you must supply the -f parameter\n" if $cDest->{force_required} && !$isForce;
	die "Error: $db_dump_dir/$source_env.sql does not exist. Please run dumpdata $source_env\n" if not -f "$db_dump_dir/$source_env.sql";
	
	# Now convert $db_dump_dir/$source_env.sql to $db_dump_dir/~$dest_env.sql
	open SOURCE, "$db_dump_dir/$source_env.sql";
	open DEST, ">$db_dump_dir/~$dest_env.sql";
	my $httpHostLengthDiff = length($cDest->{server_name}) - length($cSource->{server_name});
	
	my @httpHosts = $cSource->{server_name};
	push @httpHosts, @{$cSource->{server_aliases}} if exists $cSource->{server_aliases};
	my $httpHostsRegexp = join '|', map { quotemeta } @httpHosts;
	
	while(<SOURCE>){
		# Replace HTTP hosts
		s{(?<=://)(?:$httpHostsRegexp)(?!\.)}  #s{(?<=://)\Q$cSource->{server_name}\E(?!\.)}
		 {$cDest->{server_name}}g;
		
		#Fix serialized PHP, e.g.:
		# s:24:\"http://example.com-local
		# s:51:\"link:http://example.com-local/ - Google Blog Search
		s{(?<=s:)(\d+)(?=:\\"[^"]*\w+://(?:$httpHostsRegexp))}
		 {$1 + $httpHostLengthDiff;}ge;
		
		# Replace remaining hostnames left over for WordPress MU
		s{(?<=')(?:$httpHostsRegexp)(?=')}
		 {$cDest->{server_name}}g;
		
		print DEST;
	}
	
	close SOURCE;
	close DEST;
	
	my $db_host = $cDest->{db_host} || $cDest->{server_name};
	system("$args{p} $db_dump_dir/~$dest_env.sql") if exists $args{p} && $args{p};
	system("mysql $mysql_verbose_switch -h $db_host -u $cDest->{db_user} --password=\"$cDest->{db_password}\" $cDest->{db_name} < $db_dump_dir/~$dest_env.sql");
	
	#Clean up
	#unlink("$db_dump_dir/~$dest_env.sql");
	exit;
}


