{-# LANGUAGE CPP                   #-}
{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE DeriveFoldable        #-}
{-# LANGUAGE DeriveFunctor         #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE DeriveTraversable     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}

module Servant.Client.Core.Internal.Request where

import           Prelude ()
import           Prelude.Compat

import           Control.DeepSeq
                 (NFData (..))
import           Control.Monad.Catch
                 (Exception)
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy    as LBS
import           Data.Int
                 (Int64)
import           Data.Semigroup
                 ((<>))
import qualified Data.Sequence           as Seq
import           Data.Text
                 (Text)
import           Data.Text.Encoding
                 (encodeUtf8)
import           Data.Typeable
                 (Typeable)
import           GHC.Generics
                 (Generic)
import           Network.HTTP.Media
                 (MediaType, mainType, parameters, subType)
import           Network.HTTP.Types
                 (Header, HeaderName, HttpVersion (..), Method, QueryItem,
                 Status (..), http11, methodGet)
import           Servant.API
                 (ToHttpApiData, toEncodedUrlPiece, toHeader)

-- | A type representing possible errors in a request
--
-- Note that this type substantially changed in 0.12.
data ServantError =
  -- | The server returned an error response
    FailureResponse Response
  -- | The body could not be decoded at the expected type
  | DecodeFailure Text Response
  -- | The content-type of the response is not supported
  | UnsupportedContentType MediaType Response
  -- | The content-type header is invalid
  | InvalidContentTypeHeader Response
  -- | There was a connection error, and no response was received
  | ConnectionError Text
  deriving (Eq, Show, Generic, Typeable)

instance Exception ServantError

instance NFData ServantError where
    rnf (FailureResponse res)            = rnf res
    rnf (DecodeFailure err res)          = rnf err `seq` rnf res
    rnf (UnsupportedContentType mt' res) =
        mediaTypeRnf mt' `seq`
        rnf res
      where
        mediaTypeRnf mt =
            rnf (mainType mt) `seq`
            rnf (subType mt) `seq`
            rnf (parameters mt)
    rnf (InvalidContentTypeHeader res)   = rnf res
    rnf (ConnectionError err)            = rnf err

data RequestF a = Request
  { requestPath        :: a
  , requestQueryString :: Seq.Seq QueryItem
  , requestBody        :: Maybe (RequestBody, MediaType)
  , requestAccept      :: Seq.Seq MediaType
  , requestHeaders     :: Seq.Seq Header
  , requestHttpVersion :: HttpVersion
  , requestMethod      :: Method
  } deriving (Generic, Typeable)

type Request = RequestF Builder.Builder

-- | The request body. A replica of the @http-client@ @RequestBody@.
data RequestBody
  = RequestBodyLBS LBS.ByteString
  | RequestBodyBS BS.ByteString
  | RequestBodyBuilder Int64 Builder.Builder
  | RequestBodyStream Int64 ((IO BS.ByteString -> IO ()) -> IO ())
  | RequestBodyStreamChunked ((IO BS.ByteString -> IO ()) -> IO ())
  | RequestBodyIO (IO RequestBody)
  deriving (Generic, Typeable)

data GenResponse a = Response
  { responseStatusCode  :: Status
  , responseHeaders     :: Seq.Seq Header
  , responseHttpVersion :: HttpVersion
  , responseBody        :: a
  } deriving (Eq, Show, Generic, Typeable, Functor, Foldable, Traversable)

instance NFData a => NFData (GenResponse a) where
    rnf (Response sc hs hv body) =
        rnfStatus sc `seq`
        rnf hs `seq`
        rnfHttpVersion hv `seq`
        rnf body
      where
        rnfStatus (Status code msg) = rnf code `seq` rnf msg
        rnfHttpVersion (HttpVersion _ _) = () -- HttpVersion fields are strict

type Response = GenResponse LBS.ByteString
type StreamingResponse = GenResponse (IO BS.ByteString)

-- A GET request to the top-level path
defaultRequest :: Request
defaultRequest = Request
  { requestPath = ""
  , requestQueryString = Seq.empty
  , requestBody = Nothing
  , requestAccept = Seq.empty
  , requestHeaders = Seq.empty
  , requestHttpVersion = http11
  , requestMethod = methodGet
  }

appendToPath :: Text -> Request -> Request
appendToPath p req
  = req { requestPath = requestPath req <> "/" <> toEncodedUrlPiece p }

appendToQueryString :: Text       -- ^ param name
                    -> Maybe Text -- ^ param value
                    -> Request
                    -> Request
appendToQueryString pname pvalue req
  = req { requestQueryString = requestQueryString req
                        Seq.|> (encodeUtf8 pname, encodeUtf8 <$> pvalue)}

addHeader :: ToHttpApiData a => HeaderName -> a -> Request -> Request
addHeader name val req
  = req { requestHeaders = requestHeaders req Seq.|> (name, toHeader val)}

-- | Set body and media type of the request being constructed.
--
-- The body is set to the given bytestring using the 'RequestBodyLBS'
-- constructor.
--
-- @since 0.12
--
setRequestBodyLBS :: LBS.ByteString -> MediaType -> Request -> Request
setRequestBodyLBS b t req
  = req { requestBody = Just (RequestBodyLBS b, t) }

-- | Set body and media type of the request being constructed.
--
-- @since 0.12
--
setRequestBody :: RequestBody -> MediaType -> Request -> Request
setRequestBody b t req = req { requestBody = Just (b, t) }
