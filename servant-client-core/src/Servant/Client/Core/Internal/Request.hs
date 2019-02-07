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
import           Data.Bifoldable
                 (Bifoldable (..))
import           Data.Bifunctor
                 (Bifunctor (..))
import           Data.Bitraversable
                 (Bitraversable (..), bifoldMapDefault, bimapDefault)
import qualified Data.ByteString                      as BS
import qualified Data.ByteString.Builder              as Builder
import qualified Data.ByteString.Lazy                 as LBS
import           Data.Semigroup
                 ((<>))
import qualified Data.Sequence                        as Seq
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
                 http11, methodGet)
import           Servant.API
                 (ToHttpApiData, toEncodedUrlPiece, toHeader, SourceIO)

mediaTypeRnf :: MediaType -> ()
mediaTypeRnf mt =
    rnf (mainType mt) `seq`
    rnf (subType mt) `seq`
    rnf (parameters mt)

data RequestF body path = Request
  { requestPath        :: path
  , requestQueryString :: Seq.Seq QueryItem
  , requestBody        :: Maybe (body, MediaType)
  , requestAccept      :: Seq.Seq MediaType
  , requestHeaders     :: Seq.Seq Header
  , requestHttpVersion :: HttpVersion
  , requestMethod      :: Method
  } deriving (Generic, Typeable, Eq, Show, Functor, Foldable, Traversable)

instance Bifunctor RequestF where bimap = bimapDefault
instance Bifoldable RequestF where bifoldMap = bifoldMapDefault
instance Bitraversable RequestF where
    bitraverse f g r = mk
        <$> traverse (bitraverse f pure) (requestBody r)
        <*> g (requestPath r)
      where
        mk b p = r { requestBody = b, requestPath = p }

instance (NFData path, NFData body) => NFData (RequestF body path) where
    rnf r =
        rnf (requestPath r)
        `seq` rnf (requestQueryString r)
        `seq` rnfB (requestBody r)
        `seq` rnf (fmap mediaTypeRnf (requestAccept r))
        `seq` rnf (requestHeaders r)
        `seq` requestHttpVersion r
        `seq` rnf (requestMethod r)
      where
        rnfB Nothing        = ()
        rnfB (Just (b, mt)) = rnf b `seq` mediaTypeRnf mt

type Request = RequestF RequestBody Builder.Builder

-- | The request body. A replica of the @http-client@ @RequestBody@.
data RequestBody
  = RequestBodyLBS LBS.ByteString
  | RequestBodyBS BS.ByteString
  | RequestBodySource (SourceIO LBS.ByteString)
  deriving (Generic, Typeable)

instance Show RequestBody where
    showsPrec d (RequestBodyLBS lbs) = showParen (d > 10)
        $ showString "RequestBodyLBS "
        . showsPrec 11 lbs

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
