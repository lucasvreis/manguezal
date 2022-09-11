{-# OPTIONS_GHC -Wno-orphans #-}

module Site.Org (Route, Model (..)) where

import Site.Org.Cache (Cache)
import Data.IxSet.Typed qualified as Ix
import Ema
import Site.Org.LaTeX (processKaTeX, processLaTeX)
import Optics.Operators
import Org.Parser (defaultOrgOptions, parseOrgIO)
import Site.Org.OrgAttach (renderAttachment)
import Relude.Extra (minimumOn1, toPairs)
import Site.Org.Render (OndimOutput (OAsset))
import Site.Org.Model
import Site.Org.Options (latexOptions)
import Site.Org.Options qualified as O
import Site.Org.Process
import Site.Org.Render (renderPost)
import System.FilePath ((</>))
import System.UnionMount (FileAction (..))
import System.UnionMount qualified as UM
import Site.Org.Graph (renderGraph)

instance EmaSite Route where
  type SiteArg Route = (O.Options, TVar Cache)
  type SiteOutput Route = OndimOutput
  siteInput _ (opt, cache) =
    Dynamic
      <$> UM.unionMount sources include exclude model0 \chg ->
        appEndo . mconcat . coerce . join
          <$> forM (toPairs chg) \((), chg') ->
            forM (toPairs chg') \(file, fa) ->
              let deleteAll m =
                    let matching = m Ix.@= fromRawPath file
                     in foldr Ix.delete m matching
               in case fa of
                    Refresh _ ls -> do
                      let source = snd $ minimumOn1 fst (fst <$> ls)
                          absfp = source </> file
                      doc <-
                        parseOrgIO defaultOrgOptions absfp
                          >>= processLaTeX (latexOptions opt) cache absfp
                          >>= processKaTeX absfp
                      -- >>= processAttachInDoc TODO
                      newPages <- loadOrgFile opt source file doc
                      pure $ pages %~ Ix.insertList newPages . deleteAll
                    Delete -> pure $ #_mPages %~ deleteAll
    where
      sources = fromList (zip (zip [(1 :: Int) ..] (O.mount opt)) (O.mount opt))
      include = [((), "**/*.org")]
      exclude = O.exclude opt

  siteOutput rp m =
    pure . \case
      Route_Graph -> OAsset $ renderGraph m
      Route_Page identifier -> renderPost identifier rp m
      Route_Attach path -> OAsset $ const $ pure $ renderAttachment path m
