# NAME

OpenAPI::Client::OpenAI - A client for the OpenAI API

# SYNOPSIS

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

# DESCRIPTION

OpenAPI::Client::OpenAI is a client for the OpenAI API built on
top of [OpenAPI::Client](https://metacpan.org/pod/OpenAPI%3A%3AClient). This module automatically handles the API
key authentication according to the provided environment.

# WARNING

Due to the extremely rapid development of OpenAI's API, this module may may
not be up-to-date with the latest changes. Further releases of this module may
break your code if OpenAI changes their API.

# METHODS

## Constructor

### new

    my $client = OpenAPI::Client::OpenAI->new( $specification, %options );

Create a new OpenAI API client. The following options can be provided:

- `$specification`

    The path to the OpenAPI specification file (YAML). Defaults to the
    "openai.yaml" file in the distribution's "share" directory.

    You can find the latest version of this file at
    [https://github.com/openai/openai-openapi](https://github.com/openai/openai-openapi).

Additional options are passed to the parent class, OpenAPI::Client, with the
exception of the following extra options:

- `assistants`

    If set to a true value, this will allow access to the Assistants API.

        my $client = OpenAPI::Client::OpenAI->new(
            undef,    # use the default specification file
            assistants => 1,    # enable the Assistants API
        );

# METHODS

For the parameters for each method, please consult the `share/openapi.yaml`
document, or the OpenAI API specification you passed to the constructor, if
different.

## listAssistants

Returns a list of assistants.

    my $response = $client->listAssistants( { body => \%params });

## createAssistant

Create an assistant with a model and instructions.

    my $response = $client->createAssistant( { body => \%params });

## deleteAssistant

Delete an assistant.

    my $response = $client->deleteAssistant( { body => \%params });

## getAssistant

Retrieves an assistant.

    my $response = $client->getAssistant( { body => \%params });

## modifyAssistant

Modifies an assistant.

    my $response = $client->modifyAssistant( { body => \%params });

## createSpeech

Generates audio from the input text.

    my $response = $client->createSpeech( { body => \%params });

## createTranscription

Transcribes audio into the input language.

    my $response = $client->createTranscription( { body => \%params });

## createTranslation

Translates audio into English.

    my $response = $client->createTranslation( { body => \%params });

## listBatches

List your organization's batches.

    my $response = $client->listBatches( { body => \%params });

## createBatch

Creates and executes a batch from an uploaded file of requests.

    my $response = $client->createBatch( { body => \%params });

## retrieveBatch

Retrieves a batch.

    my $response = $client->retrieveBatch( { body => \%params });

## cancelBatch

Cancels an in-progress batch.

    my $response = $client->cancelBatch( { body => \%params });

## createChatCompletion

Creates a model response for the given chat conversation.

    my $response = $client->createChatCompletion( { body => \%params });

## createCompletion

Creates a completion for the provided prompt and parameters.

    my $response = $client->createCompletion( { body => \%params });

## createEmbedding

Creates an embedding vector representing the input text.

    my $response = $client->createEmbedding( { body => \%params });

## listFiles

Returns a list of files that belong to the user's organization.

    my $response = $client->listFiles( { body => \%params });

## createFile

Upload a file that can be used across various endpoints.

    my $response = $client->createFile( { body => \%params });

## deleteFile

Delete a file.

    my $response = $client->deleteFile( { body => \%params });

## retrieveFile

Returns information about a specific file.

    my $response = $client->retrieveFile( { body => \%params });

## downloadFile

Returns the contents of the specified file.

    my $response = $client->downloadFile( { body => \%params });

## listPaginatedFineTuningJobs

List your organization's fine-tuning jobs.

    my $response = $client->listPaginatedFineTuningJobs( { body => \%params });

## createFineTuningJob

Creates a fine-tuning job which begins the process of creating a new model from a given dataset.

    my $response = $client->createFineTuningJob( { body => \%params });

## retrieveFineTuningJob

Get info about a fine-tuning job.

    my $response = $client->retrieveFineTuningJob( { body => \%params });

## cancelFineTuningJob

Immediately cancel a fine-tune job.

    my $response = $client->cancelFineTuningJob( { body => \%params });

## listFineTuningJobCheckpoints

List checkpoints for a fine-tuning job.

    my $response = $client->listFineTuningJobCheckpoints( { body => \%params });

## listFineTuningEvents

Get status updates for a fine-tuning job.

    my $response = $client->listFineTuningEvents( { body => \%params });

## createImageEdit

Creates an edited or extended image given an original image and a prompt.

    my $response = $client->createImageEdit( { body => \%params });

## createImage

Creates an image given a prompt.

    my $response = $client->createImage( { body => \%params });

## createImageVariation

Creates a variation of a given image.

    my $response = $client->createImageVariation( { body => \%params });

## listModels

Lists the currently available models, and provides basic information about each one such as the owner and availability.

    my $response = $client->listModels( { body => \%params });

## deleteModel

Delete a fine-tuned model. You must have the Owner role in your organization to delete a model.

    my $response = $client->deleteModel( { body => \%params });

## retrieveModel

Retrieves a model instance, providing basic information about the model such as the owner and permissioning.

    my $response = $client->retrieveModel( { body => \%params });

## createModeration

Classifies if text is potentially harmful.

    my $response = $client->createModeration( { body => \%params });

## createThread

Create a thread.

    my $response = $client->createThread( { body => \%params });

## createThreadAndRun

Create a thread and run it in one request.

    my $response = $client->createThreadAndRun( { body => \%params });

## deleteThread

Delete a thread.

    my $response = $client->deleteThread( { body => \%params });

## getThread

Retrieves a thread.

    my $response = $client->getThread( { body => \%params });

## modifyThread

Modifies a thread.

    my $response = $client->modifyThread( { body => \%params });

## listMessages

Returns a list of messages for a given thread.

    my $response = $client->listMessages( { body => \%params });

## createMessage

Create a message.

    my $response = $client->createMessage( { body => \%params });

## deleteMessage

Deletes a message.

    my $response = $client->deleteMessage( { body => \%params });

## getMessage

Retrieve a message.

    my $response = $client->getMessage( { body => \%params });

## modifyMessage

Modifies a message.

    my $response = $client->modifyMessage( { body => \%params });

## listRuns

Returns a list of runs belonging to a thread.

    my $response = $client->listRuns( { body => \%params });

## createRun

Create a run.

    my $response = $client->createRun( { body => \%params });

## getRun

Retrieves a run.

    my $response = $client->getRun( { body => \%params });

## modifyRun

Modifies a run.

    my $response = $client->modifyRun( { body => \%params });

## cancelRun

Cancels a run that is \`in\_progress\`.

    my $response = $client->cancelRun( { body => \%params });

## listRunSteps

Returns a list of run steps belonging to a run.

    my $response = $client->listRunSteps( { body => \%params });

## getRunStep

Retrieves a run step.

    my $response = $client->getRunStep( { body => \%params });

## submitToolOuputsToRun

When a run has the \`status: "requires\_action"\` and \`required\_action.type\` is \`submit\_tool\_outputs\`, this endpoint can be used to submit the outputs from the tool calls once they're all completed. All outputs must be submitted in a single request.

    my $response = $client->submitToolOuputsToRun( { body => \%params });

## listVectorStores

Returns a list of vector stores.

    my $response = $client->listVectorStores( { body => \%params });

## createVectorStore

Create a vector store.

    my $response = $client->createVectorStore( { body => \%params });

## deleteVectorStore

Delete a vector store.

    my $response = $client->deleteVectorStore( { body => \%params });

## getVectorStore

Retrieves a vector store.

    my $response = $client->getVectorStore( { body => \%params });

## modifyVectorStore

Modifies a vector store.

    my $response = $client->modifyVectorStore( { body => \%params });

## createVectorStoreFileBatch

Create a vector store file batch.

    my $response = $client->createVectorStoreFileBatch( { body => \%params });

## getVectorStoreFileBatch

Retrieves a vector store file batch.

    my $response = $client->getVectorStoreFileBatch( { body => \%params });

## cancelVectorStoreFileBatch

Cancel a vector store file

    batch. This attempts to cancel the processing of files in this batch as soon as possible.

       my $response = $client->cancelVectorStoreFileBatch( { body => \%params });

## listFilesInVectorStoreBatch

Returns a list of vector store files in a batch.

    my $response = $client->listFilesInVectorStoreBatch( { body => \%params });

## listVectorStoreFiles

Returns a list of vector store files.

    my $response = $client->listVectorStoreFiles( { body => \%params });

## createVectorStoreFile

Create a vector store file by attaching a File to a vector store.

    my $response = $client->createVectorStoreFile( { body => \%params });

## deleteVectorStoreFile

Delete a vector store file. This will remove the file from the vector store but the file itself will not be deleted. To delete the file, use the delete file endpoint.

    my $response = $client->deleteVectorStoreFile( { body => \%params });

## getVectorStoreFile

Retrieves a vector store file.

    my $response = $client->getVectorStoreFile( { body => \%params });

# ENVIRONMENT VARIABLES

The following environment variables are used by this module:

- OPENAI\_API\_KEY

    The API key used to authenticate requests to the OpenAI API.

# SEE ALSO

[OpenAPI::Client](https://metacpan.org/pod/OpenAPI%3A%3AClient) - the deprecated precursor to this module.

# AUTHOR

Nelson Ferraz, <nferraz@gmail.com>

# CONTRIBUTORS

Curtis "Ovid" Poe, <curtis.poe@gmail.com>

# COPYRIGHT AND LICENSE

Copyright (C) 2023-2024 by Nelson Ferraz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.0 or,
at your option, any later version of Perl 5 you may have available.
