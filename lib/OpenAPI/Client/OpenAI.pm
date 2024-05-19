package OpenAPI::Client::OpenAI;

use strict;
use warnings;

use Carp;
use File::ShareDir ':ALL';
use File::Spec::Functions qw(catfile);

use Mojo::Base 'OpenAPI::Client';
use Mojo::URL;

our $VERSION = '0.02';

sub new {
    my ( $class, $specification ) = ( shift, shift );
    my $attrs = @_ == 1 ? shift : {@_};

    if ( !$ENV{OPENAI_API_KEY} ) {
        Carp::croak('OPENAI_API_KEY environment variable must be set');
    }

    if ( !$specification ) {
        eval {
            $specification = dist_file( 'OpenAPI-Client-OpenAI', 'openapi.yaml' );
            1;
        } or do {
            # Fallback to local share directory during development
            warn $@;
            $specification = catfile( 'share', 'openapi.yaml' );
        };
    }
    my %headers = (
        'Authorization' => "Bearer $ENV{OPENAI_API_KEY}",
    );
    if ( delete $attrs->{assistants} ) {
       $headers{'OpenAI-Beta'} = 'assistants=v1';
    }

    # 'message' => 'You must provide the \'OpenAI-Beta\' header to access the
    # Assistants API. Please try again by setting the header \'OpenAI-Beta:
    # assistants=v1\'.'

    my $self = $class->SUPER::new( $specification, %{$attrs} );

    $self->ua->on(
        start => sub {
            my ( $ua, $tx ) = @_;
            foreach my $header ( keys %headers ) {
                $tx->req->headers->header( $header => $headers{$header} );
            }
        }
    );

    return $self;
}

# install snake case aliases

{
    my %snake_case_alias = (
        createChatCompletion => 'create_chat_completion',
        createCompletion     => 'create_completion',
        createEdit           => 'create_edit',
        createEmbedding      => 'create_embedding',
        createImage          => 'create_image',
        createModeration     => 'create_moderation',
        listModels           => 'list_models',
    );

    for my $camel_case_method ( keys %snake_case_alias ) {
        no strict 'refs';
        *{"$snake_case_alias{$camel_case_method}"} = sub {
            my $self = shift;
            $self->$camel_case_method(@_);
        }
    }
}

1;

__END__

=head1 NAME

OpenAPI::Client::OpenAI - A client for the OpenAI API

=head1 SYNOPSIS

  use OpenAPI::Client::OpenAI;

  # The OPENAI_API_KEY environment variable must be set
  # See https://platform.openai.com/api-keys and ENVIRONMENT VARIABLES below
  my $client = OpenAPI::Client::OpenAI->new();

    my $tx = $client->create_completion(
        {
            body => {
                model       => 'gpt-3.5-turbo-instruct',
                prompt      => 'What is the capital of France?'
                temperature => 0, # optional, between 0 and 1, with 0 being the least random
                max_tokens  => 100, # optional, the maximum number of tokens to generate
            }
        }
    );

  my $response_data = $tx->res->json;

  print Dumper($response_data);

=head1 DESCRIPTION

OpenAPI::Client::OpenAI is a client for the OpenAI API built on
top of L<OpenAPI::Client>. This module automatically handles the API
key authentication according to the provided environment.

Note that the OpenAI API is a paid service. You will need to sign up for an
account.

=head1 WARNING

Due to the extremely rapid development of OpenAI's API, this module may may
not be up-to-date with the latest changes. Further releases of this module may
break your code if OpenAI changes their API.

=head1 METHODS

=head2 Constructor

=head3 new

    my $client = OpenAPI::Client::OpenAI->new( $specification, %options );

Create a new OpenAI API client. The following options can be provided:

=over

=item * C<$specification>

The path to the OpenAPI specification file (YAML). Defaults to the
"openai.yaml" file in the distribution's "share" directory.

You can find the latest version of this file at
L<https://github.com/openai/openai-openapi>.

=back

Additional options are passed to the parent class, OpenAPI::Client, with the
exception of the following extra options:

=over

=item * C<assistants>

If set to a true value, this will allow access to the Assistants API.

    my $client = OpenAPI::Client::OpenAI->new(
        undef,    # use the default specification file
        assistants => 1,    # enable the Assistants API
    );

=back

=head1 METHODS

For the parameters for each method, please consult the F<share/openapi.yaml>
document, or the OpenAI API specification you passed to the constructor, if
different.

=head2 listAssistants

Returns a list of assistants.

    my $response = $client->listAssistants( { body => \%params });

=head2 createAssistant

Create an assistant with a model and instructions.

    my $response = $client->createAssistant( { body => \%params });

=head2 deleteAssistant

Delete an assistant.

    my $response = $client->deleteAssistant( { body => \%params });

=head2 getAssistant

Retrieves an assistant.

    my $response = $client->getAssistant( { body => \%params });

=head2 modifyAssistant

Modifies an assistant.

    my $response = $client->modifyAssistant( { body => \%params });

=head2 createSpeech

Generates audio from the input text.

    my $response = $client->createSpeech( { body => \%params });

=head2 createTranscription

Transcribes audio into the input language.

    my $response = $client->createTranscription( { body => \%params });

=head2 createTranslation

Translates audio into English.

    my $response = $client->createTranslation( { body => \%params });

=head2 listBatches

List your organization's batches.

    my $response = $client->listBatches( { body => \%params });

=head2 createBatch

Creates and executes a batch from an uploaded file of requests.

    my $response = $client->createBatch( { body => \%params });

=head2 retrieveBatch

Retrieves a batch.

    my $response = $client->retrieveBatch( { body => \%params });

=head2 cancelBatch

Cancels an in-progress batch.

    my $response = $client->cancelBatch( { body => \%params });

=head2 createChatCompletion

Creates a model response for the given chat conversation.

    my $response = $client->createChatCompletion( { body => \%params });

=head2 createCompletion

Creates a completion for the provided prompt and parameters.

    my $response = $client->createCompletion( { body => \%params });

=head2 createEmbedding

Creates an embedding vector representing the input text.

    my $response = $client->createEmbedding( { body => \%params });

=head2 listFiles

Returns a list of files that belong to the user's organization.

    my $response = $client->listFiles( { body => \%params });

=head2 createFile

Upload a file that can be used across various endpoints.

    my $response = $client->createFile( { body => \%params });

=head2 deleteFile

Delete a file.

    my $response = $client->deleteFile( { body => \%params });

=head2 retrieveFile

Returns information about a specific file.

    my $response = $client->retrieveFile( { body => \%params });

=head2 downloadFile

Returns the contents of the specified file.

    my $response = $client->downloadFile( { body => \%params });

=head2 listPaginatedFineTuningJobs

List your organization's fine-tuning jobs.

    my $response = $client->listPaginatedFineTuningJobs( { body => \%params });

=head2 createFineTuningJob

Creates a fine-tuning job which begins the process of creating a new model from a given dataset.

    my $response = $client->createFineTuningJob( { body => \%params });

=head2 retrieveFineTuningJob

Get info about a fine-tuning job.

    my $response = $client->retrieveFineTuningJob( { body => \%params });

=head2 cancelFineTuningJob

Immediately cancel a fine-tune job.

    my $response = $client->cancelFineTuningJob( { body => \%params });

=head2 listFineTuningJobCheckpoints

List checkpoints for a fine-tuning job.

    my $response = $client->listFineTuningJobCheckpoints( { body => \%params });

=head2 listFineTuningEvents

Get status updates for a fine-tuning job.

    my $response = $client->listFineTuningEvents( { body => \%params });

=head2 createImageEdit

Creates an edited or extended image given an original image and a prompt.

    my $response = $client->createImageEdit( { body => \%params });

=head2 createImage

Creates an image given a prompt.

    my $response = $client->createImage( { body => \%params });

=head2 createImageVariation

Creates a variation of a given image.

    my $response = $client->createImageVariation( { body => \%params });

=head2 listModels

Lists the currently available models, and provides basic information about each one such as the owner and availability.

    my $response = $client->listModels( { body => \%params });

=head2 deleteModel

Delete a fine-tuned model. You must have the Owner role in your organization to delete a model.

    my $response = $client->deleteModel( { body => \%params });

=head2 retrieveModel

Retrieves a model instance, providing basic information about the model such as the owner and permissioning.

    my $response = $client->retrieveModel( { body => \%params });

=head2 createModeration

Classifies if text is potentially harmful.

    my $response = $client->createModeration( { body => \%params });

=head2 createThread

Create a thread.

    my $response = $client->createThread( { body => \%params });

=head2 createThreadAndRun

Create a thread and run it in one request.

    my $response = $client->createThreadAndRun( { body => \%params });

=head2 deleteThread

Delete a thread.

    my $response = $client->deleteThread( { body => \%params });

=head2 getThread

Retrieves a thread.

    my $response = $client->getThread( { body => \%params });

=head2 modifyThread

Modifies a thread.

    my $response = $client->modifyThread( { body => \%params });

=head2 listMessages

Returns a list of messages for a given thread.

    my $response = $client->listMessages( { body => \%params });

=head2 createMessage

Create a message.

    my $response = $client->createMessage( { body => \%params });

=head2 deleteMessage

Deletes a message.

    my $response = $client->deleteMessage( { body => \%params });

=head2 getMessage

Retrieve a message.

    my $response = $client->getMessage( { body => \%params });

=head2 modifyMessage

Modifies a message.

    my $response = $client->modifyMessage( { body => \%params });

=head2 listRuns

Returns a list of runs belonging to a thread.

    my $response = $client->listRuns( { body => \%params });

=head2 createRun

Create a run.

    my $response = $client->createRun( { body => \%params });

=head2 getRun

Retrieves a run.

    my $response = $client->getRun( { body => \%params });

=head2 modifyRun

Modifies a run.

    my $response = $client->modifyRun( { body => \%params });

=head2 cancelRun

Cancels a run that is `in_progress`.

    my $response = $client->cancelRun( { body => \%params });

=head2 listRunSteps

Returns a list of run steps belonging to a run.

    my $response = $client->listRunSteps( { body => \%params });

=head2 getRunStep

Retrieves a run step.

    my $response = $client->getRunStep( { body => \%params });

=head2 submitToolOuputsToRun

When a run has the `status: "requires_action"` and `required_action.type` is `submit_tool_outputs`, this endpoint can be used to submit the outputs from the tool calls once they're all completed. All outputs must be submitted in a single request.

    my $response = $client->submitToolOuputsToRun( { body => \%params });

=head2 listVectorStores

Returns a list of vector stores.

    my $response = $client->listVectorStores( { body => \%params });

=head2 createVectorStore

Create a vector store.

    my $response = $client->createVectorStore( { body => \%params });

=head2 deleteVectorStore

Delete a vector store.

    my $response = $client->deleteVectorStore( { body => \%params });

=head2 getVectorStore

Retrieves a vector store.

    my $response = $client->getVectorStore( { body => \%params });

=head2 modifyVectorStore

Modifies a vector store.

    my $response = $client->modifyVectorStore( { body => \%params });

=head2 createVectorStoreFileBatch

Create a vector store file batch.

    my $response = $client->createVectorStoreFileBatch( { body => \%params });

=head2 getVectorStoreFileBatch

Retrieves a vector store file batch.

    my $response = $client->getVectorStoreFileBatch( { body => \%params });

=head2 cancelVectorStoreFileBatch

Cancel a vector store file

 batch. This attempts to cancel the processing of files in this batch as soon as possible.

    my $response = $client->cancelVectorStoreFileBatch( { body => \%params });

=head2 listFilesInVectorStoreBatch

Returns a list of vector store files in a batch.

    my $response = $client->listFilesInVectorStoreBatch( { body => \%params });

=head2 listVectorStoreFiles

Returns a list of vector store files.

    my $response = $client->listVectorStoreFiles( { body => \%params });

=head2 createVectorStoreFile

Create a vector store file by attaching a File to a vector store.

    my $response = $client->createVectorStoreFile( { body => \%params });

=head2 deleteVectorStoreFile

Delete a vector store file. This will remove the file from the vector store but the file itself will not be deleted. To delete the file, use the delete file endpoint.

    my $response = $client->deleteVectorStoreFile( { body => \%params });

=head2 getVectorStoreFile

Retrieves a vector store file.

    my $response = $client->getVectorStoreFile( { body => \%params });

=head1 ENVIRONMENT VARIABLES

The following environment variables are used by this module:

=over 4

=item * OPENAI_API_KEY

The API key used to authenticate requests to the OpenAI API.

=back

=head1 SEE ALSO

L<OpenAPI::Client> - the deprecated precursor to this module.

=head1 AUTHOR

Nelson Ferraz, E<lt>nferraz@gmail.comE<gt>

=head1 CONTRIBUTORS

Curtis "Ovid" Poe, E<lt>curtis.poe@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023-2024 by Nelson Ferraz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
