%%%-----------------------------------------------------------------------------
%%% @doc The behaviour for `http_cache' response stores
%%%
%%% Keep in mind that for a unique combination of a request's method, URL, body and bucket,
%%% there still can be several different responses, depending on the `vary' and
%%% `content-range' headers. A so called candidate is a response that matches request
%%% information independently of these two headers. The main `http_cache' module is in charge
%%% of selecting a response that satisfies these two headers.
%%%
%%% One possibility is to include `vary' and `content-range' in the key. The `content-range'
%%% header, if the returned response is a `206 Partial Response', is stored in the request
%%% metadata (`#{parsed_headers := #{<<"content-range">> := {bytes, 3, 10, 20}}}' for instance).
%%%
%%% This is why the process is the following:
%%% <ol>
%%%   <li> `http_cache' request all the potential responses (candidates) using `list_candidates/1' </li>
%%%   <li> `http_cache' selects the freshest response whose `vary' and `content-range' headers match </li>
%%%   <li> `http_cache' request the response with `get_response/1'</li>
%%% </ol>

-module(http_cache_store_behaviour).

-export_type([request_key/0, candidate/0, stored_response/0, response_ref/0, url_digest/0,
              opts/0]).

-type status() :: pos_integer().
%% HTTP status
-type headers() :: [{binary(), binary()}].
%% Request or response headers
-type vary_headers() :: #{binary() := binary() | undefined}.
%% Headers taken into account by vary
-type body() :: binary().
% The body transmitted to the backend
%
% This is a binary so as to optimize copying around data: an IOlist would have to
% be copied whereas (big) binaries are simply reference-counted.
-type candidate() ::
    {RespRef :: response_ref(),
     Status :: status(),
     RespHeaders :: headers(),
     VaryHeaders :: vary_headers(),
     RespMetadata :: response_metadata()}.
-type opts() :: any().
%% Options for the backend store
-type request_key() :: binary().
%% A unique, opaque, key for a request taking into account the request's information (method,
%% URL, body and bucket)
-type stored_response() ::
    {Status :: status(),
     Headers :: headers(),
     BodyOrFile :: body() | {file, file:name_all()},
     Metadata :: response_metadata()}.
%% Stored HTTP response with its metadata
%%
%% The body can either be a binary (for example if the
%% response is stored in memory) or a file (if the response is stored on disk).
-type response_metadata() ::
    #{created := timestamp(),
      expires := timestamp(),
      grace := timestamp(),
      ttl_set_by := header | heuristics,
      parsed_headers := #{binary() => term()},
      alternate_keys := [alternate_key()]}.
-type response_ref() :: term().
%% Opaque backend's reference to a response, returned by
%% `http_cache:get/2' and used as a parameter by `http_cache:notify_response_used/2'.
-type url_digest() :: binary().
%% Opaque URL digest as computed by the main module
-type alternate_key() :: term().
%% Alternate key attached to a stored response
-type timestamp() :: non_neg_integer().
%% UNIX timestamp in seconds
-type http_cache_response() :: {status(), headers(), body()}.
%% An HTTP response
-type invalidation_result() ::
    {ok, NbInvalidatedResponses :: non_neg_integer() | undefined} | {error, term()}.

%% Normalized headers on which the response varies

-callback list_candidates(RequestKey :: request_key(), Opts :: opts()) -> [candidate()].
%% Returns the list of candidates matching a request, via its request key
-callback get_response(RespRef :: response_ref(), Opts :: opts()) ->
                          stored_response() | undefined.
%% Returns a response from a response reference returned by `list_candidates/1'
-callback put(RequestKey :: request_key(),
              UrlDigest :: url_digest(),
              VaryHeaders :: vary_headers(),
              Response :: http_cache_response(),
              RespMetadata :: response_metadata(),
              Opts :: opts()) ->
                 ok | {error, term()}.
%% Stores a response and associated metadata
-callback notify_response_used(RespRef :: response_ref(), Opts :: opts()) ->
                                  ok | {error, term()}.
%% Notify that a response was used. A LRU cache, for instance, would update the timestamp
%% the response was last used
-callback invalidate_url(UrlDigest :: url_digest(), Opts :: opts()) ->
                            invalidation_result().
%% Invalidates all responses for a given URL digest
-callback invalidate_by_alternate_key([AltKeys :: alternate_key()], Opts :: opts()) ->
                                         invalidation_result().

%% Invalidates all responses that has been tag with one of the alternate keys

-optional_callbacks([invalidate_by_alternate_key/2]).
