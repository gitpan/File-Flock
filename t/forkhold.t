
use FindBin;
require "$FindBin::Bin/wrap.tm";
use File::Slurp;
use Time::HiRes qw(sleep);
use POSIX qw(_exit);
use File::Flock::Subprocess;
use File::Flock;

dirwrap(sub {
	do_test();
});

our $dir;  # set in wrap.pm

sub do_test
{
	die unless $dir;
	test_lock_held_across_fork();
}

sub test_lock_held_across_fork()
{
	my $lock1 = "$dir/lhaf1";
	my $lock2 = "$dir/lhaf2";

	if (dofork()) {
		require Test::More;
		import Test::More tests => 7;
		lock($lock1);
		my $l = File::Flock->new($lock2);
		write_file("$dir/gate1", "");

		POSIX::_exit(0) unless dofork();
		write_file("$dir/gate2", "");

		sleep(0.1) while ! -e "$dir/gate3";
		ok(! -e "$dir/gotlock1a", "lock held");
		ok(! -e "$dir/gotlock1b", "obj lock held");
		ok(! -e "$dir/gotlock2a", "child lock held");
		ok(! -e "$dir/gotlock2b", "child obj lock held");
		unlock($lock1);
		write_file("$dir/gate4", "");

		sleep(0.1) while ! -e "$dir/gate5";
		ok(-e "$dir/gotlock3a", "lock released");
		ok(! -e "$dir/gotlock3b", "obj lock not released");
		$l->unlock();
		write_file("$dir/gate6", "");

		sleep(0.1) while ! -e "$dir/gate7";
		ok(-e "$dir/gotlock4", "obj lock released");
		write_file("$dir/gate8", "");
	} else {
		sleep(0.1) while ! -e "$dir/gate1";
		# parent has locked lock
		write_file("$dir/gotlock1a", "") if lock($lock1, undef, 'nonblocking');
		write_file("$dir/gotlock1b", "") if lock($lock2, undef, 'nonblocking');

		sleep(0.1) while ! -e "$dir/gate2";
		write_file("$dir/gotlock2a", "") if lock($lock1, undef, 'nonblocking');
		write_file("$dir/gotlock2b", "") if lock($lock2, undef, 'nonblocking');
		write_file("$dir/gate3", "");

		sleep(0.1) while ! -e "$dir/gate4";
		write_file("$dir/gotlock3a", "") if lock($lock1, undef, 'nonblocking');
		write_file("$dir/gotlock3b", "") if lock($lock2, undef, 'nonblocking');
		write_file("$dir/gate5", "");

		sleep(0.1) while ! -e "$dir/gate6";
		write_file("$dir/gotlock4", "") if lock($lock2, undef, 'nonblocking');
		write_file("$dir/gate7", "");
		sleep(0.1) while ! -e "$dir/gate8";
		exit(0);
	}
}

sub dofork
{
	my $p = fork();
	die unless defined $p;
	return $p;
}

