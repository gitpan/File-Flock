
use ExtUtils::MakeMaker;

WriteMakefile( 
	'VERSION_FROM' => 'lib/File/Flock.pm',
	'NAME'	  => 'File::Flock',
	'dist' => { COMPRESS=>"gzip", SUFFIX=>"gz" },
	($] >= 5.005 ? 
	    ('ABSTRACT' => 'Wrapper for flock() to make file locking trivial',
	    'AUTHOR' => 'David Muir Sharnoff <muir@idiom.com>') : ()),
	);

