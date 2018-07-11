{-# LANGUAGE FlexibleContexts, TypeApplications, MonoLocalBinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module    : Aura.Commands.L
-- Copyright : (c) Colin Woodbury, 2012 - 2018
-- License   : GPL3
-- Maintainer: Colin Woodbury <colin@fosskers.ca>
--
-- Handle all @-L@ flags - those which involve the pacman log file.

module Aura.Commands.L
  ( viewLogFile
  , searchLogFile
  , logInfoOnPkg
  ) where

import           Aura.Colour (red, dtot)
import           Aura.Core (report)
import           Aura.Languages
import           Aura.Settings
import           Aura.Utils (entrify, colourCheck)
import           BasePrelude hiding (FilePath)
import           Control.Monad.Freer
import           Control.Monad.Freer.Reader
import qualified Data.Set as S
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           Data.Text.Prettyprint.Doc
import           Shelly
import           Utilities

---

-- | The contents of the Pacman log file.
newtype Log = Log [T.Text]

data LogEntry = LogEntry { _pkgName :: T.Text, _firstInstall :: T.Text, _upgrades :: Word, _recent :: [T.Text] }

viewLogFile :: (Member (Reader Settings) r, Member IO r) => Eff r ()
viewLogFile = do
  pth <- asks (either id id . logPathOf . commonConfigOf)
  void . send . shelly @IO . loudSh $ run_ "less" [toTextIgnore pth]

-- Very similar to `searchCache`. But is this worth generalizing?
searchLogFile :: Settings -> T.Text -> IO ()
searchLogFile ss input = do
  let pth = either id id . logPathOf $ commonConfigOf ss
  logFile <- T.lines <$> shelly (readfile pth)
  traverse_ T.putStrLn $ searchLines (Regex input) logFile

logInfoOnPkg :: (Member (Reader Settings) r, Member IO r) => S.Set T.Text -> Eff r ()
logInfoOnPkg pkgs =
  unless (null pkgs) $ do
    ss <- ask
    let pth = either id id . logPathOf $ commonConfigOf ss
    logFile <- fmap (Log . T.lines) . send . shelly @IO $ readfile pth
    let (bads, goods) = partitionEithers . map (logLookup logFile) $ toList pkgs
    report red reportNotInLog_1 bads
    send . traverse_ T.putStrLn $ map (renderEntry ss) goods

logLookup :: Log -> T.Text -> Either T.Text LogEntry
logLookup (Log lns) p = case matches of
  []    -> Left p
  (h:t) -> Right $ LogEntry p
                   (T.take 16 $ T.tail h)
                   (fromIntegral . length $ filter (T.isInfixOf " upgraded ") t)
                   (reverse . take 5 $ reverse t)
  where matches = filter (T.isInfixOf (" " <> p <> " (")) lns

renderEntry :: Settings -> LogEntry -> T.Text
renderEntry ss (LogEntry pn fi us rs) =
  dtot . colourCheck ss $ entrify ss fields entries <> hardline <> recent <> hardline
  where fields  = logLookUpFields $ langOf ss
        entries = map pretty [ pn, fi, T.pack (show us), "" ]
        recent  = vsep $ map pretty rs
