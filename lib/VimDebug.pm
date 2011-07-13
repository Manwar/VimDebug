# ABSTRACT: A base class for VimDebug modules

=head1 SYNOPSIS

   package VimDebug;

   use strict;
   use warnings;
   use base qw(VimDebug);

   sub start {
      my $self = shift or confess;
      my $path               = shift or die;
      my @commandLineOptions = @_;

      # this regexe aids in parsing debugger output.  it is required.
      $self->dbgrPromptRegex($dbgrPromptRegex);

      $self->SUPER::startDebugger("perl -d $path @commandLineOptions");
      return undef;
   }

   # 'n' is the command accepted by your language's debugger
   sub next { return 'n' }
   sub step { return 's' }
   sub cont { return 'c' }
   # ...etc
   

=head1 DESCRIPTION

This is a base class for developers wanting to add support to vimdebug for
their language. 

=cut

package VimDebug;

use strict;
use warnings;
use Class::Accessor::Fast;
use base qw(Class::Accessor::Fast);

use Carp;
use Data::Dumper::Concise;
use IO::Pty;
use IPC::Run;

$| = 1;

my $READ;
my $WRITE;

my $COMPILER_ERROR = "compiler error";
my $RUNTIME_ERROR  = "runtime error";
my $APP_EXITED     = "application exited";
my $DBGR_READY     = "debugger ready";

__PACKAGE__->mk_accessors(
    qw(dbgrCmd timer dbgr stop lineNumber filePath translatedInput READ WRITE
       debug original status oldOut)
);


sub start {
   my $self = shift or confess;

   # initialize some variables
   $self->original('');
   $self->out('');
   $self->oldOut('');
   $self->translatedInput([]);
   $self->debug(1);
   $self->timer(IPC::Run::timeout(10, exception => 'timed out'));

   # spawn debugger process
   $self->dbgr(
      IPC::Run::start(
         $self->dbgrCmd, 
         '<pty<', \$WRITE,
         '>pty>', \$READ,
         $self->timer
      )
   );
   return undef;
}

sub write {
   my $self = shift or confess;
   my $c    = shift or confess;
   $self->stop(0);
   $WRITE .= "$c\n";
   return;
}

=head2 read

Returns 1 when done
Returns 0 if its not done

=cut
sub read {
   my $self = shift or confess;
   $| = 1;

   my $dbgrPromptRegex    = $self->dbgrPromptRegex;
   my $compilerErrorRegex = $self->compilerErrorRegex;
   my $runtimeErrorRegex  = $self->runtimeErrorRegex;
   my $appExitedRegex     = $self->appExitedRegex;

print ".";
   $self->timer->reset();
   eval { $self->dbgr->pump_nb() };
print ":";
   my $out = $READ;
print "|";

#   if ($@ =~ /process ended prematurely/ and length($READ) != 0) {
#       print "::read(): weird: $out\n" if $self->debug;
#       undef $@;
#       return 0;
#   }
   if ($@ =~ /process ended prematurely/) {
       print "::read(): process ended prematurely\n" if $self->debug;
       undef $@;
       return 1;
   }
   elsif ($@) {
       die $@;
   }

   if ($self->stop) {
       print "::read(): stopping\n" if $self->debug;
       $WRITE .= "";
       $self->timer->reset();
       $self->dbgr->pump() until $READ =~ /$dbgrPromptRegex/;
   }

   if    ($out eq $self->original)       { return 0                       }
   elsif ($out =~ /$dbgrPromptRegex/)    { $self->status($DBGR_READY)     }
   elsif ($out =~ /$compilerErrorRegex/) { $self->status($COMPILER_ERROR) }
   elsif ($out =~ /$runtimeErrorRegex/)  { $self->status($RUNTIME_ERROR)  }
   elsif ($out =~ /$appExitedRegex/)     { $self->status($APP_EXITED)     }
   else                                  { return 0                       }

   print "::read(): out: [$out]\n" if $self->debug;
   $self->original($out);
print "original done\n";
   $self->out($out);
print "out done\n";
   $self->parseOutput($out);
print "parseout done\n";

print "done";
   return 1;
}

=head2 out($out)

Remove ornaments (like <CTL-M> or irrelevant error messages or whatever) from
text. 

Returns $out cleansed
=cut
sub out {
   my $self = shift or confess;
   my $out = '';

   if (@_) {
      $out = shift;

      # remove the old output that keeps accumulating
      $self->oldOut( $self->oldOut . $self->{out} );
      my $oldOutLen = length $self->oldOut;
      $out = substr($out, $oldOutLen) 
         if $oldOutLen > 0;
        
      # vim is not displaying newline characters correctly for some reason.
      # this localizes the newlines.
      $out =~ s/(?:\015{1,2}\012|\015|\012)/\n/sg;

      # save
      $self->{out} = $out;
   }

   return $self->{out};
}

=head2 lineNumber($number)

If $number parameter is used, the lineNumber class attribute is set using that
value.  If no parameters are passed, the current value of the lineNumber class
attribute is returned.

=head2 filePath($path)

If $path parameter is used, the filePath class attribute is set using that
value.  If no parameters are passed, the current value of the filePath class
attribute is returned.

=head2 dbgrPromptRegex($regex)

If $regex parameter is used, the dbgrPromptRegex class attribute is set using that
value.  If no parameters are passed, the current value of the dbgrPromptRegex class
attribute is returned.


=head1 SEE ALSO

L<Devel::ebug>, L<perldebguts>


=head1 AUTHOR

Eric Johnson, cpan at iijo : :dot: : org

=head1 COPYRIGHT

Copyright (C) 2003 - 3090, Eric Johnson

This module is GPL.

=cut

1;
