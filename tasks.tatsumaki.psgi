#!/usr/bin/env perl
use strict;
use warnings;

use Tatsumaki::Error;
use Tatsumaki::Application;
use Tatsumaki::Server;

=head1 SQLITE3 SCHEMA

Create the database on /tmp/:

    sqlite3 /tmp/tasks.sqlite

At the prompt, create the needed table:

    CREATE TABLE Task (
        id          integer not null primary key autoincrement,
        isdone      tinyint default 0,
        description text    default ''
    );

And insert some data to start with:

    INSERT INTO Task (isdone,description) VALUES (1,'Insert stuff in table');
    INSERT INTO Task (isdone,description) VALUES (0,'Get a coffee');
    INSERT INTO Task (isdone,description) VALUES (0,'Finish documentation');

=cut

package Tasks::Model;
use ORLite {
  'package' => 'Tasks::Model',
  'file'    => '/tmp/tasks.sqlite',
};

package Tasks::Controller::List;
use parent qw/Tatsumaki::Handler/;
use JSON;

# the controller used to GET a list of tasks, or POST a new task.

# GET a list of all tasks
sub get {
  my ( $self, $query ) = @_;
  my @tasks;
  Tasks::Model::Task->iterate(
    sub {
      push @tasks,
        {
        guid        => '/task/' . $_->{id},
        description => $_->{description},
        isDone      => $_->{isdone} ? 1 : 0,
        };
    }
  );
  $self->write( to_json( { content => \@tasks } ) );
}

# POST a new task
sub post {
  my ($self) = @_;
  my $data;
  my $json = JSON->new;
  $json->allow_barekey(1);
  $json->allow_singlequote(1);
  eval { $data = $json->decode( $self->request->content ); };
  Tatsumaki::Error::HTTP->throw(400) if ($@);    # not a JSON, or can't parse
  Tatsumaki::Error::HTTP->throw(400)
    unless ( defined $data->{description} and defined $data->{isDone} );
  my $task = Tasks::Model::Task->create(
    isdone => $data->{isDone} ? 1 : 0,
    description => $data->{description},
  );
  $self->response->status(201);
  $self->response->headers( [ 'Location' => '/task/' . $task->id, ] );
}

package Tasks::Controller::Content;
use parent qw/Tatsumaki::Handler/;
use JSON;

# the controller used to GET a specific task, or DELETE an existing task.

# GET a task's data
sub get {
  my ( $self, $id ) = @_;
  my $task;
  eval { $task = Tasks::Model::Task->load($id); };
  Tatsumaki::Error::HTTP->throw(404) if ($@);    # not found in db
  $self->write(
    to_json(
      {
        content => {
          guid        => '/task/' . $task->id,
          description => $task->description,
          order       => $task->id,
          isDone      => $task->isdone,
        }
      }
    )
  );
}

# PUT new details for a task (isDone or description)
sub put {
  my ( $self, $id ) = @_;
  my $task;
  eval { $task = Tasks::Model::Task->load($id); };
  Tatsumaki::Error::HTTP->throw(404) if ($@);    # not found in db
  my $json = JSON->new;
  $json->allow_barekey(1);
  $json->allow_singlequote(1);
  my $data;
  eval { $data = $json->decode( $self->request->content ); };
  Tatsumaki::Error::HTTP->throw(400) if ($@);    # not a JSON, or can't parse
  Tatsumaki::Error::HTTP->throw(400)
    unless ( defined $data->{description} or defined $data->{isDone} );
  my $new_isdone = defined $data->{isDone}      ? int( $data->{isDone} ) : $task->isdone;
  my $new_desc   = defined $data->{description} ? $data->{description}   : $task->description;
  Tasks::Model->do( 'UPDATE Task SET isDone=?, description=? WHERE id=?',
    {}, $new_isdone, $new_desc, $task->id, );
  $self->response->status(201);
  $self->response->headers( [ 'Location' => '/task/' . $task->id, ] );
}

# DELETE a task
sub delete {
  my ( $self, $id ) = @_;
  my $task;
  eval { $task = Tasks::Model::Task->load($id); };
  Tatsumaki::Error::HTTP->throw(404) if ($@);    # not found in db
  $task->delete;
  $self->response->status(200);
  $self->write('');
}

1;

package main;

my $app = Tatsumaki::Application->new(
  [
    '/tasks'      => 'Tasks::Controller::List',
    '/task/(\d+)' => 'Tasks::Controller::Content',
  ]
);
return $app;

