module Parser where

import Models (Token (..))
import Tokenizer

type IsTrue = Bool

data Programm
  = Programm [Programmklausel] Ziel
  | Programm' [(VarSeq, Programmklausel)] (VarSeq, Ziel)
  deriving (Show, Eq)

data Programmklausel = Pk1 NVLTerm | Pk2 NVLTerm Ziel deriving (Show, Eq)

newtype Ziel = Ziel [Literal] deriving (Show, Eq)

data Literal = Literal IsTrue LTerm deriving (Show, Eq)

data NVLTerm = NVLTerm String [LTerm] deriving (Show, Eq)

data LTerm = LTVar String | LTNVar NVLTerm deriving (Show, Eq)

data Tree
  = TP Programm
  | TPk Programmklausel
  | TZ Ziel
  | TL Literal
  | TLL [Literal]
  | TName String
  | TNVLT NVLTerm
  | TLT LTerm
  | TLLT [LTerm]
  deriving (Show, Eq)

type VarSeq = [String]

type Rule = [Token] -> (Tree, [Token])

-- TODO: Better error handling
-- TODO: Maybe implement functor and just use first function
lookAhead :: [Token] -> Token
lookAhead [] = error "List of symbols unexpectedly went empty whilst parsing"
lookAhead (x : _) = x

tail' :: [Token] -> [Token]
tail' [] = error "Jack, don't let go"
tail' (_ : xs) = xs

lTerm :: Rule
lTerm [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
lTerm (tok : toks) = case tok of
  (Variable str) -> (TLT $ LTVar str, toks)
  (Name str) ->
    let (TNVLT nvlTerm, toks') = nichtVariableLTerm (tok : toks)
     in (TLT $ LTNVar nvlTerm, toks')
  _ -> error $ "Expected Variable or Name but got " ++ show tok

name :: Rule
name [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
name ((Name str) : toks) = (TName str, toks)
name (tok : _) = error $ "Expected a name but got: " ++ show tok

-- Helper function
teilNichtVariableLTerm :: Rule
teilNichtVariableLTerm toks =
  let (TLT ltvar, toks') = lTerm toks
   in case lookAhead toks' of
        And ->
          let (TLLT ltvars, toks'') = teilNichtVariableLTerm (tail' toks')
           in (TLLT $ ltvar : ltvars, toks'')
        KlammerZu -> (TLLT [ltvar], tail' toks')
        _ -> error $ "Expected AND or close parenthesis but got: " ++ show (lookAhead toks')

nichtVariableLTerm :: Rule
nichtVariableLTerm toks =
  let (TName str, toks') = name toks
   in case lookAhead toks' of
        KlammerAuf ->
          let (TLLT lterms, toks'') = teilNichtVariableLTerm (tail' toks')
           in (TNVLT $ NVLTerm str lterms, toks'')
        _ -> (TNVLT $ NVLTerm str [], toks')

literal :: Rule
literal [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
literal (Not : toks) =
  let (TLT lterm, toks') = lTerm toks
   in (TL $ Literal False lterm, toks')
literal toks@((Variable _) : toks') =
  let (TLT lterm, toks') = lTerm toks
   in (TL $ Literal True lterm, toks')
literal toks@((Name _) : toks') =
  let (TLT lterm, toks') = lTerm toks
   in (TL $ Literal True lterm, toks')
literal (tok : _) =
  error $ "Expected Not, Variable or Name but got " ++ show tok

-- Helper function
reoccurringLiteral :: Rule
reoccurringLiteral toks =
  let (TL lit, toks') = literal toks
   in case lookAhead toks' of
        And ->
          let (TLL lits, toks'') = reoccurringLiteral (tail' toks')
           in (TLL $ lit : lits, toks'')
        Punkt -> (TLL [lit], tail' toks')
        _ -> error $ "Expected And or Punkt but got " ++ show (lookAhead toks')

ziel :: Rule
ziel [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
ziel (Implikation : toks) = case lookAhead toks of
  Not ->
    let (TLL literals, toks') = reoccurringLiteral toks
     in (TZ $ Ziel literals, toks')
  (Variable _) ->
    let (TLL literals, toks') = reoccurringLiteral toks
     in (TZ $ Ziel literals, toks')
  (Name _) ->
    let (TLL literals, toks') = reoccurringLiteral toks
     in (TZ $ Ziel literals, toks')
  _ -> error $ "Expected Not, Variable or Name but got " ++ show (lookAhead toks)
ziel (tok : _) = error $ "Expected an Implikation but got " ++ show tok

programmklausel :: Rule
programmklausel [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
programmklausel toks@((Name _) : toks') =
  let (TNVLT nvlTerm, toks'') = nichtVariableLTerm toks
   in case lookAhead toks'' of
        Punkt -> (TPk $ Pk1 nvlTerm, tail' toks'')
        Implikation ->
          let (TZ z, toks''') = ziel toks''
           in (TPk $ Pk2 nvlTerm z, toks''')
        _ -> error $ "Expected Punkt or Implikation but got " ++ show (lookAhead toks'')
programmklausel (tok : _) = error $ "Expected Name but got " ++ show tok

programm :: Rule
programm [] = error "List of tokens unexpectedly went empty but should've ended on Ende"
programm (tok : toks) = case tok of
  (Name _) ->
    let (TPk pk, toks'') = programmklausel (tok : toks)
     in case lookAhead toks'' of
          (Name _) ->
            let (TP (Programm pks z), toks''') = programm toks''
             in (TP $ Programm (pk : pks) z, toks''')
          Implikation ->
            let (TZ z, toks''') = ziel toks''
             in (TP $ Programm [pk] z, toks''')
          _ -> error $ "Expected Name or Implikation but got " ++ show tok
  Implikation ->
    let (TZ z, toks'') = ziel (tok : toks)
     in (TP $ Programm [] z, toks'')
  _ -> error $ "Expected Name or Implikation but got " ++ show tok

parse :: [Token] -> Tree
parse toks =
  let (tree, toks') = programm toks
   in case lookAhead toks' of
        Ende -> newTree tree
        _ ->
          error $
            "Expected to finish with Ende but it didn't.\n"
              ++ "These tokens failed parsing: "
              ++ show toks'
              ++ "."
              ++ "They could be parsed thus far:\n"
              ++ show tree

--Sucht Variablen des fertigen Baumes und hängt die relevanten an die jeweiligen Klauseln/das Ziel
newTree :: Tree -> Tree
newTree (TP (Programm x y)) = TP (Programm' (newPk x) (newZiel y))
newTree _ = error "Unvollständiger Programmbaum"

--Geht einzelne Programmklauseln durch und sucht nach Variablen
newPk :: [Programmklausel] -> [(VarSeq, Programmklausel)]
newPk = map (\x -> newPk' x [] [])

--Schaut direkt auf die NichtVariablenLTerme und den LTermen in den Programmklauseln und sammelt Variablen
newPk' :: Programmklausel -> [LTerm] -> VarSeq -> (VarSeq, Programmklausel)
--Für Programmklauseln ohne Ziele
newPk' (Pk1 (NVLTerm x [])) akk varSeq = (removeDuplicates varSeq, Pk1 (NVLTerm x akk))
newPk' (Pk1 (NVLTerm x (lTerm : rest))) akk varSeq = case lTerm of
  LTVar s -> newPk' (Pk1 (NVLTerm x rest)) (akk ++ [lTerm]) (varSeq ++ [s])
  LTNVar nt -> newPk' (Pk1 (NVLTerm x rest)) (akk ++ [lTerm]) (newNVLT nt varSeq)
--Für Programmklauseln mit Zielen
newPk' (Pk2 (NVLTerm x []) ziel) akk varSeq = (removeDuplicates $ varSeq ++ newZiel' ziel [], Pk2 (NVLTerm x akk) ziel)
newPk' (Pk2 (NVLTerm x (lTerm : rest)) ziel) akk varSeq = case lTerm of
  LTVar s -> newPk' (Pk2 (NVLTerm x rest) ziel) (akk ++ [lTerm]) (varSeq ++ [s])
  LTNVar nt -> newPk' (Pk2 (NVLTerm x rest) ziel) (akk ++ [lTerm]) (newNVLT nt varSeq)

--Sammelt Variablen in NichtVariablenLTermen und schaut auch auf LTerme
newNVLT :: NVLTerm -> VarSeq -> VarSeq
newNVLT (NVLTerm _ []) varSeq = varSeq
newNVLT (NVLTerm x (lTerm : rest)) varSeq = case lTerm of
  LTVar s -> newNVLT (NVLTerm x rest) (varSeq ++ [s])
  LTNVar nt -> newNVLT (NVLTerm x rest) (varSeq ++ newNVLT nt [])

--Geht Ziele durch und sucht nach Variablen
newZiel :: Ziel -> (VarSeq, Ziel)
newZiel ziel = (newZiel' ziel [], ziel)

--Geht die LTerme in den Literalen der Ziele durch und sammelt Variablen
newZiel' :: Ziel -> VarSeq -> VarSeq
newZiel' (Ziel []) varSeq = removeDuplicates varSeq
newZiel' (Ziel ((Literal _ lTerm) : rest)) varSeq = case lTerm of
  LTVar s -> newZiel' (Ziel rest) (varSeq ++ [s])
  LTNVar nt -> newZiel' (Ziel rest) (varSeq ++ newNVLT nt [])

removeDuplicates :: [String] -> [String]
removeDuplicates = removeDuplicates' []

removeDuplicates' :: [String] -> [String] -> [String]
removeDuplicates' akk [] = akk
removeDuplicates' akk (x : xs)
  | x `elem` akk = removeDuplicates' akk xs
  | otherwise = removeDuplicates' (akk ++ [x]) xs