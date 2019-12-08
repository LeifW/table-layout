-- | This module provides tools to layout text as grid or table. Besides basic
-- things like specifying column positioning, alignment on the same character
-- and length restriction it also provides advanced features like justifying
-- text and fancy tables with styling support.
--
{-# LANGUAGE RecordWildCards #-}
module Text.Layout.Table
    ( -- * Layout combinators
      -- | Specify how a column is rendered with the combinators in this
      -- section. Sensible default values are provided with 'def'.

      module Data.Default.Class

      -- ** Columns
    , ColSpec
    , column
    , numCol
    , fixedCol
    , fixedLeftCol
      -- ** Length of columns
    , LenSpec
    , expand
    , fixed
    , expandUntil
    , fixedUntil
      -- ** Positional alignment
    , Position
    , H
    , left
    , right
    , center
      -- ** Alignment of cells at characters
    , AlignSpec
    , noAlign
    , charAlign
    , predAlign
    , dotAlign
      -- ** Cut marks
    , CutMark
    , noCutMark
    , singleCutMark
    , doubleCutMark

      -- * Basic grid layout
    , Row
    , grid
    , gridLines
    , gridString

      -- * Grid modification functions
    , altLines
    , checkeredCells

      -- * Table layout
      -- ** Grouping rows
    , RowGroup
    , rowsG
    , rowG
    , colsG
    , colsAllG

      -- ** Headers
    , HeaderColSpec
    , headerColumn
    , HeaderSpec
    , fullH
    , titlesH

      -- ** Layout
    , tableLines
    , tableString

      -- * Text justification
      -- $justify
    , justify
    , justifyText

      -- * Vertical column positioning
    , Col
    , colsAsRowsAll
    , colsAsRows
    , top
    , bottom
    , V

      -- * Table styles
    , module Text.Layout.Table.Style

      -- * Column modification functions
    , pad
    , trimOrPad
    , align
    , alignFixed

      -- * Column modifaction primitives
      -- | These functions are provided to be reused. For example if someone
      -- wants to render their own kind of tables.
    , ColModInfo
    , widthCMI
    , unalignedCMI
    , ensureWidthCMI
    , ensureWidthOfCMI
    , columnModifier
    , AlignInfo
    , widthAI
    , deriveColModInfos
    , deriveAlignInfo
    , OccSpec
    ) where

-- TODO AlignSpec:   multiple alignment points - useful?
-- TODO RowGroup:    optional: vertical group labels
-- TODO RowGroup:    optional: provide extra layout for a RowGroup
-- TODO ColSpec:     add some kind of combinator to construct ColSpec values (e.g. via Monoid, see optparse-applicative)

import qualified Control.Arrow                               as A
import           Data.List
import           Data.Semigroup
import           Data.Default.Class
import           Data.Default.Instances.Base                 ()

import           Text.Layout.Table.Cell
import           Text.Layout.Table.Justify
import           Text.Layout.Table.Primitives.AlignInfo
import           Text.Layout.Table.Primitives.Basic
import           Text.Layout.Table.Primitives.ColumnModifier
import           Text.Layout.Table.Primitives.Header
import           Text.Layout.Table.Spec.AlignSpec
import           Text.Layout.Table.Spec.ColSpec
import           Text.Layout.Table.Spec.CutMark
import           Text.Layout.Table.Spec.HeaderColSpec
import           Text.Layout.Table.Spec.HeaderSpec
import           Text.Layout.Table.Spec.LenSpec
import           Text.Layout.Table.Spec.OccSpec
import           Text.Layout.Table.Spec.Position
import           Text.Layout.Table.Spec.RowGroup
import           Text.Layout.Table.Spec.Util
import           Text.Layout.Table.StringBuilder
import           Text.Layout.Table.Style
import           Text.Layout.Table.Vertical

-------------------------------------------------------------------------------
-- Layout types and combinators
-------------------------------------------------------------------------------

-- | Align all text at the first dot from the left. This is most useful for
-- floating point numbers.
dotAlign :: AlignSpec
dotAlign = charAlign '.'

-- | Numbers are positioned on the right and aligned on the floating point dot.
numCol :: ColSpec
numCol = column def right dotAlign def

-- | Fixes the column length and positions according to the given 'Position'.
fixedCol :: Int -> Position H -> ColSpec
fixedCol l pS = column (fixed l) pS def def

-- | Fixes the column length and positions on the left.
fixedLeftCol :: Int -> ColSpec
fixedLeftCol i = fixedCol i left

-------------------------------------------------------------------------------
-- Basic layout
-------------------------------------------------------------------------------

-- | Modifies cells according to the column specification.
grid :: [ColSpec] -> [Row String] -> [Row String]
grid specs tab = zipWith ($) cmfs <$> tab
  where
    -- | The column modification function for each column.
    cmfs = zipWith (uncurry columnModifier) (map (position A.&&& cutMark) specs) cmis
    cmis = deriveColModInfos' specs tab

-- | Behaves like 'grid' but produces lines by joining with whitespace.
gridLines :: [ColSpec] -> [Row String] -> [String]
gridLines specs = fmap unwords . grid specs

-- | Behaves like 'gridLines' but produces a string by joining with the newline
-- character.
gridString :: [ColSpec] -> [Row String] -> String
gridString specs = concatLines . gridLines specs

-------------------------------------------------------------------------------
-- Grid modification functions
-------------------------------------------------------------------------------

-- | Applies functions to given lines in a alternating fashion. This makes it
-- easy to color lines to improve readability in a row.
altLines :: [a -> b] -> [a] -> [b]
altLines = zipWith ($) . cycle

-- | Applies functions to cells in a alternating fashion for every line, every
-- other line gets shifted by one. This is useful for distinguishability of
-- single cells in a grid arrangement.
checkeredCells  :: (a -> b) -> (a -> b) -> [[a]] -> [[b]]
checkeredCells f g = zipWith altLines $ cycle [[f, g], [g, f]]

-------------------------------------------------------------------------------
-- Advanced layout
-------------------------------------------------------------------------------

-- | Create a 'RowGroup' by aligning the columns vertically. The position is
-- specified for each column.
colsG :: [Position V] -> [Col String] -> RowGroup
colsG ps = rowsG . colsAsRows ps

-- | Create a 'RowGroup' by aligning the columns vertically. Each column uses
-- the same vertical positioning.
colsAllG :: Position V -> [Col String] -> RowGroup
colsAllG p = rowsG . colsAsRowsAll p

-- | Layouts a pretty table with an optional header. Note that providing fewer
-- layout specifications than columns or vice versa will result in not showing
-- the redundant ones.
tableLines :: [ColSpec]  -- ^ Layout specification of columns
           -> TableStyle -- ^ Visual table style
           -> HeaderSpec -- ^ Optional header details
           -> [RowGroup] -- ^ Rows which form a cell together
           -> [String]
tableLines specs TableStyle { .. } header rowGroups =
    topLine : addHeaderLines (rowGroupLines ++ [bottomLine])
  where
    -- Helpers for horizontal lines that will put layout characters arround and
    -- in between a row of the pre-formatted grid.

    -- | Draw a horizontal line that will use the delimiters around 'cols'
    -- appropriately and visually separate by 'hSpace'.
    hLineDetail hSpace delimL delimM delimR cols
                  = intercalate [hSpace] $ [delimL] : intersperse [delimM] cols ++ [[delimR]]

    -- | A simplified version of 'hLineDetail' that will use the same delimiter
    -- for everything.
    hLine hSpace delim
                  = hLineDetail hSpace delim delim delim

    -- | Generate columns filled with 'sym'.
    fakeColumns sym
                  = map (`replicate` sym) colWidths


    -- Horizontal seperator lines that occur in a table.
    topLine       = hLineDetail realTopH realTopL realTopC realTopR $ fakeColumns realTopH
    bottomLine    = hLineDetail groupBottomH groupBottomL groupBottomC groupBottomR $ fakeColumns groupBottomH
    groupSepLine  = hLineDetail groupSepH groupSepLC groupSepC groupSepRC $ fakeColumns groupSepH
    headerSepLine = hLineDetail headerSepH headerSepLC headerSepC headerSepRC $ fakeColumns headerSepH

    -- Vertical content lines
    rowGroupLines = intercalate [groupSepLine] $ map (map (hLine ' ' groupV) . applyRowMods . rows) rowGroups

    -- Optional values for the header
    (addHeaderLines, fitHeaderIntoCMIs, realTopH, realTopL, realTopC, realTopR)
                  = case header of
        HeaderHS headerColSpecs hTitles
               ->
            let headerLine    = hLine ' ' headerV (zipWith ($) headerRowMods hTitles)
                headerRowMods = zipWith3 headerCellModifier
                                         headerColSpecs
                                         cMSs
                                         cMIs
            in
            ( (headerLine :) . (headerSepLine :)
            , fitTitlesCMI hTitles posSpecs
            , headerTopH
            , headerTopL
            , headerTopC
            , headerTopR
            )
        NoneHS ->
            ( id
            , id
            , groupTopH
            , groupTopL
            , groupTopC
            , groupTopR
            )

    cMSs          = map cutMark specs
    posSpecs      = map position specs
    applyRowMods  = map (zipWith ($) rowMods)
    rowMods       = zipWith3 columnModifier posSpecs cMSs cMIs
    cMIs          = fitHeaderIntoCMIs $ deriveColModInfos' specs $ concatMap rows rowGroups
    colWidths     = map widthCMI cMIs

-- | Does the same as 'tableLines', but concatenates lines.
tableString :: [ColSpec]  -- ^ Layout specification of columns
            -> TableStyle -- ^ Visual table style
            -> HeaderSpec -- ^ Optional header details
            -> [RowGroup] -- ^ Rows which form a cell together
            -> String
tableString specs style header rowGroups = concatLines $ tableLines specs style header rowGroups

-------------------------------------------------------------------------------
-- Text justification
-------------------------------------------------------------------------------

-- $justify
-- Text can easily be justified and distributed over multiple lines. Such
-- columns can be combined with other columns.
