#!/usr/bin/perl

use strict;
use warnings;
use Socket;

use Test::More no_plan => 1;
use Test::WWW::Mechanize;
use Test::Moose;

use MooseX::Daemonize::Pid::File;

BEGIN {
    use_ok('FCGI::Engine');
}

use Cwd;
use File::Spec::Functions;

my $CWD                = Cwd::cwd;
$ENV{MX_DAEMON_STDOUT} = catfile($CWD, 'Out.txt');
$ENV{MX_DAEMON_STDERR} = catfile($CWD, 'Err.txt');

{
    package Counter;
    use Moose;
    
    my $count = 0;
    
    sub handler { 
        print("Content-type: text/html\r\n\r\n");
        print(++$count);
    }
}

my $SOCKET  = '/tmp/050_lighttpd_basic_test.socket';
my $PIDFILE = '/tmp/050_lighttpd_basic_test.pid';

@ARGV = (
    '--listen'  => $SOCKET,
    '--pidfile' => $PIDFILE,
    '--daemon'
);

my $e = FCGI::Engine->new_with_options(handler_class => 'Counter');
isa_ok($e, 'FCGI::Engine');
does_ok($e, 'MooseX::Getopt');

ok($e->is_listening, '... we are listening');
is($e->listen, $SOCKET, '... we have the right socket location');

is($e->nproc, 1, '... we have the default 1 proc');

ok($e->has_pidfile, '... we have a pidfile');
is($e->pidfile, $PIDFILE, '... we have the right pidfile');

ok($e->should_detach, '... we should daemonize');

is($e->manager, 'FCGI::Engine::ProcManager', '... we have the default manager (FCGI::ProcManager)');
ok(!$e->has_pre_fork_init, '... we dont have any pre-fork-init');

unless ( fork ) {
    $e->run;
    exit;
}
else {
    sleep(1);    # 1 seconds should be enough for everything to happen
    
    ok(-S $SOCKET, '... our socket was created');
    ok(-f $PIDFILE, '... our pidfile was created');

    my $pid = MooseX::Daemonize::Pid::File->new(file => $e->pidfile);
    isa_ok($pid, 'MooseX::Daemonize::Pid::File');

    ok($pid->is_running, '... our daemon is running (pid: ' . $pid->pid . ')');
    
    system(qw[lighttpd -f t/lighttpd_confs/050_lighttpd_basic_test.conf]);

    my $mech = Test::WWW::Mechanize->new;
    for (1 .. 5) {
        $mech->get_ok('http://localhost:8080/count', '... got the page okay');
        $mech->content_is($_, '... got the content we expected');    
    }

    kill TERM => `cat /tmp/lighttpd.pid`;

    kill TERM => $pid->pid;
    
    sleep(1); # give is a moment to die ...

    ok(!$pid->is_running, '... our daemon is no longer running (pid: ' . $pid->pid . ')');

    unlink $SOCKET;
}

#unlink $ENV{MX_DAEMON_STDOUT};
#unlink $ENV{MX_DAEMON_STDERR};
