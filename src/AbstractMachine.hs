module AbstractMachine where

import Data.Char (toLower)
import Data.Maybe (fromJust, fromMaybe)
import Debug.Trace
import Models
import Parser
import Stack
import Tokenizer

--Flagregister
type B = Bool

--AdressRegister
type T = Pointer

type C = Pointer

type R = Pointer

type P = Pointer

type E = Pointer

type Up = Pointer

type Ut = Pointer

type Tt = Pointer

--ZählRegister
type Pc = Int

type Sc = Int

type Ac = Pointer

--Kombination der Register, AddressRegs/Addressreg für MiniL, AddressRegs' ??, FullAddresReg für ML

type AddressRegs = (B, T, C, R, P, Up, E, Ut, Tt, Pc, Sc, Ac)

-- Zielcode is the returntype of L Code Translation
type Zielcode = Stack Command

-- Speicherbereiche
-- TODO: Muss erweitert werden mit Env
type Speicherbereiche = (MLStack, Us, Trail)

type MLStack = Stack StackElement

type Env = Stack

type Us = Stack StackElement

type Trail = Stack StackElement

--Was den Funktionen übegeben wird

type RegisterKeller = (AddressRegs, Speicherbereiche)

newtype Atom = A String deriving (Eq)

newtype Variable = V String deriving (Eq)

type Arity = Int

data Argument
  = ATNot
  | ATNeg
  | ATPos
  | ATAtom Atom
  | ATStr Atom Arity
  | ATChp -- Für push (GroundL)
  | ATEndAtom
  | ATBegEnv
  | ATEndEnv Int
  | ATVar Variable Pointer
  | ATPush
  | ATUnify
  deriving (Eq, Show)

{-------------------------
  Datentypen für ML
 ----------------------------}
data Linearization = Linearization String Arity deriving (Eq, Show)

data Exp = ExpLin Linearization | ExpVar Variable deriving (Show)

instance Show Variable where
  show (V str) = str

{----------------------------------------
  Bestehende Datentypen
 -----------------------------------------}

--data Stack Argument (könnte bspw ENdEnv o.ä. enthalten)

instance Show Atom where
  show (A str) = str

-- Data type that covers all types needed for the code stack of the abstract machine
data StackElement
  = CodeAddress Pointer
  | StackAddress Pointer
  | UsAddress Pointer
  | TrailAddress Pointer
  | CodeArg Argument
  deriving (Eq)

instance Show StackElement where
  show (CodeAddress adr) = "c" ++ show adr
  show (StackAddress adr) = "s" ++ show adr
  show (UsAddress adr) = "u" ++ show adr
  show (TrailAddress adr) = "t" ++ show adr
  show (CodeArg arg) = case arg of
    ATNot -> "not"
    ATNeg -> "neg"
    ATPos -> "pos"
    ATPush -> "push"
    ATUnify -> "unify"
    ATChp -> "chp"
    ATBegEnv -> "BegEnv"
    (ATEndEnv n) -> "EndEnv " ++ show n
    ATEndAtom -> "EndAtom"
    (ATAtom atom) -> show atom
    (ATStr atom arity) -> concat ["STR", " ", show atom, "/", show arity]
    (ATVar variable element) -> concat ["VAR", " ", show variable, " ", show element]

--helper
stackItemToInt :: StackElement -> Maybe Pointer
stackItemToInt (CodeAddress x) = Just x
stackItemToInt (StackAddress x) = Just x
stackItemToInt (UsAddress x) = Just x
stackItemToInt (TrailAddress x) = Just x
stackItemToInt (CodeArg (ATVar symb addr)) = Just addr
stackItemToInt (CodeArg (ATStr symb arity)) = Just (Pointer arity)
stackItemToInt _ = Nothing

safePointerFromStackAtLocation :: Pointer -> Stack StackElement -> Pointer
safePointerFromStackAtLocation addr stack =
  fromMaybe Nil (stackItemToInt $ stackItemAtLocation addr stack)

stackReplaceAtLocationMLStack i elem = stackReplaceAtLocation i elem (StackAddress Nil)

-- Commands, necessary for having a List of named partially applied functions
data Command
  = Unify (Argument -> RegisterKeller -> RegisterKeller) Argument
  | Push (Argument -> (RegisterKeller -> Zielcode -> RegisterKeller)) Argument
  | Call (RegisterKeller -> Zielcode -> RegisterKeller)
  | Return (Argument -> RegisterKeller -> RegisterKeller) Argument
  | Backtrack (RegisterKeller -> Zielcode -> RegisterKeller)
  | Prompt (RegisterKeller -> Zielcode -> IO ())

instance Show Command where
  show (Unify _ args) = "unifyML " ++ show args
  show (Push _ args) = "pushML " ++ show args
  show (Call _) = "callML"
  show (Return _ args) = "returnML " ++ show args
  show (Backtrack _) = "backtrackML"
  show (Prompt _) = "promptML"

instance Eq Command where
  (==) (Unify _ expr1) (Unify _ expr2) = expr1 == expr2
  (==) (Push _ expr1) (Push _ expr2) = expr1 == expr2
  (==) (Call _) (Call _) = True
  (==) (Backtrack _) (Backtrack _) = True
  (==) (Return _ arg1) (Return _ arg2) = arg1 == arg2
  (==) (Prompt _) (Prompt _) = True
  (==) _ _ = False

{----------------------------------------------------------
   Translations
-----------------------------------------------------------}

genCode :: Tree -> Zielcode
genCode parsetree = üb parsetree (Stack [])

-- Main translation function.
-- Takes a parse tree and tries to generate a so called "Zielcode".
-- The latter is a Stack of Commands, such as push and backtrack.
-- TODO: Check if commands are added in the right order (Stack is LIFO/FILO)
üb :: Tree -> Zielcode -> Zielcode
--ML

--Üb(VarSeq, :- Sequenz.)
üb (TP (Programm' [] (varSeq, Ziel literals))) akk =
  übBody literals (übEnv (map V varSeq) (akk <> Stack [Push push ATBegEnv])) <> Stack [Prompt prompt]
--Üb(VarSeq, Atom :- Sequenz.)
üb (TP (Programm' ((varSeq, Pk2 atom (Ziel literals)) : rest) ziel)) akk =
  üb
    (TP (Programm' rest ziel))
    (übBody literals (übHead atom (übEnv (map V varSeq) (akk <> Stack [Push push ATBegEnv]))) <> Stack [Return returnL ATPos])
--Üb(VarSeq, Atom.)
üb (TP (Programm' ((varSeq, Pk1 atom) : rest) ziel)) akk =
  üb
    (TP (Programm' rest ziel))
    (übHead atom (übEnv (map V varSeq) (akk <> Stack [Push push ATBegEnv])) <> Stack [Return returnL ATPos])
--MiniL/GroundL
-- If there are no Programmklauseln
üb (TP (Programm [] (Ziel lits))) akk = üb (TZ (Ziel lits)) akk
-- If there are Programmklauseln
üb (TP (Programm klauseln@(pklausel : pklauseln) (Ziel lits))) akk
  | null pklauseln = üb (TZ (Ziel lits)) $ üb (TPk pklausel) akk
  | otherwise = üb (TP (Programm pklauseln (Ziel lits))) $ üb (TPk pklausel) akk
-- Üb(Atom.)
üb (TPk (Pk1 atom)) akk = übHead atom akk <> Stack [Return returnL ATPos]
-- Üb(Atom :- Seq)
üb (TPk (Pk2 atom (Ziel seq))) akk =
  let akk' = übHead atom akk
   in übBody seq akk' <> Stack [Return returnL ATPos]
üb (TZ (Ziel literals)) akk = übBody literals akk <> Stack [Prompt prompt]
üb _ akk = error $ "Failure in :- Seq translation." ++ show akk

-- übHead(Atom.)
übHead :: NVLTerm -> (Zielcode -> Zielcode)
übHead atom@(NVLTerm _ _) = übUnify (linearize atom)

übBody :: [Literal] -> Zielcode -> Zielcode
-- ÜbBody([not Atom | Sequenz])
übBody ((Literal False (LTNVar nvlt@(NVLTerm atom subatoms))) : seq) akk =
  übBody
    seq
    $ übPush
      (linearize nvlt)
      (akk <> Stack [Push push ATNot, Push push ATChp])
      <> Stack
        [ Push push ATEndAtom,
          Call call,
          Backtrack backtrack,
          Return returnL ATNeg,
          Backtrack backtrack
        ]
-- Üb_Body([Atom | Sequenz])
übBody ((Literal _ (LTNVar nvlt@(NVLTerm atom subatoms))) : seq) akk =
  übBody
    seq
    $ übPush (linearize nvlt) (akk <> Stack [Push push ATChp])
      <> Stack [Push push ATEndAtom, Call call, Backtrack backtrack]
übBody [] akk = akk
übBody _ _ = error "Failure in übBody."

übEnv :: [Variable] -> Stack Command -> Stack Command
übEnv var = übEnvHelper var $ length var

type VariableCount = Int

übEnvHelper :: [Variable] -> VariableCount -> Stack Command -> Stack Command
übEnvHelper [] n akk = akk <> Stack [Push push $ ATEndEnv n]
übEnvHelper (var : seq) n akk =
  übEnvHelper seq n (akk <> Stack [Push push (ATVar var Nil)])

übPush :: [Exp] -> Zielcode -> Zielcode
-- ÜbPush([])
übPush [] akk = akk
übPush [ExpVar var] akk = akk <> Stack [Push push (ATVar var Nil)]
-- ÜbPush(Symbol/Arity)
übPush [ExpLin (Linearization sym arity)] akk =
  akk <> Stack [Push push $ ATStr (A sym) arity]
-- ÜbPush([Exp | Sequenz])
übPush (exp : seq) akk = übPush seq $ übPush [exp] akk

übUnify :: [Exp] -> Zielcode -> Zielcode
-- übUnify([])
übUnify [] akk = akk
-- übUnify(Symbol/Arity)
übUnify (ExpLin (Linearization sym arity) : rest) akk =
  übUnify rest (akk <> Stack [Unify unify (ATStr (A sym) arity), Backtrack backtrack])
-- übUnify(Symbol)
übUnify (ExpVar var : rest) akk =
  übUnify rest (akk <> Stack [Unify unify (ATVar var Nil), Backtrack backtrack])

{--------------------------------------------------------------
   Instruktionen
 ---------------------------------------------------------------}

-- Push für GroundL
push :: Argument -> (RegisterKeller -> (Zielcode -> RegisterKeller))
-- push Str Symbol Arity
push
  arg@(ATStr (A sym) arity)
  ( (b, t, c, r, p, up, e, ut, tt, pc, sc, ac),
    (stack, us, trail)
    )
  _ =
    ( (b, t + 1, c, r, p + 1, up, e, ut, tt, pc, sc, ac),
      ( stackReplaceAtLocationMLStack
          (t + 1)
          (CodeArg arg)
          stack,
        us,
        trail
      )
    )
-- Push CHP
push ATChp ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) code =
  ( (b, t + 6, t + 1, t + 2, p + 1, t + 7, e, Pointer (-1), tt, 0, sc, Nil),
    ( stackReplaceAtLocationMLStack
        (t + 6)
        (StackAddress 9998)
        ( stackReplaceAtLocationMLStack
            (t + 5)
            (TrailAddress tt)
            ( stackReplaceAtLocationMLStack
                (t + 4)
                (StackAddress e)
                ( stackReplaceAtLocationMLStack
                    (t + 3)
                    (StackAddress 9999)
                    ( stackReplaceAtLocationMLStack
                        (t + 3)
                        (StackAddress 9999)
                        ( stackReplaceAtLocationMLStack
                            (t + 2)
                            (StackAddress c)
                            ( stackReplaceAtLocationMLStack
                                (t + 1)
                                (CodeAddress $ cFirst code)
                                stack
                            )
                        )
                    )
                )
            )
        ),
      us,
      trail
    )
  )
push ATBegEnv ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) _ =
  ((b, t, c, r, p + 1, up, Nil, ut, tt, pc, sc, ac), (stack, us, trail))
push
  var@(ATVar sym _)
  rs@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  _ =
    ( (b, t + 1, c, r, p + 1, up, e, ut, tt, pc, sc, ac),
      ( stackReplaceAtLocationMLStack
          (t + 1)
          (CodeArg $ ATVar sym (sAdd rs var ATPush))
          stack,
        us,
        trail
      )
    )
push ATEndAtom ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) _ =
  ( (b, t, c, r, p + 1, up, e, ut, tt, pc, sc, ac),
    ( stackReplaceAtLocationMLStack
        (c + 5)
        (StackAddress t)
        ( stackReplaceAtLocationMLStack
            (c + 2)
            (CodeAddress $ p + 3)
            stack
        ),
      us,
      trail
    )
  )
push arg@(ATEndEnv n) (regs@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) _ =
  ( (b, t + 1, c, r, p + 1, up, (t + 1) -<- n, ut, tt, pc, sc, ac),
    ( stackReplaceAtLocationMLStack (t + 1) (CodeArg arg) stack,
      us,
      trail
    )
  )
push _ _ _ = error "Case not covered by GroundL pattern matching for push."

-- ML call Befehl
call :: RegisterKeller -> Zielcode -> RegisterKeller
call ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail)) code =
  if stackItemAtLocation c stack == CodeAddress Nil
    then ((True, t, c, r, p + 1, up, e, ut, tt, pc, sc, ac), stacks)
    else
      let p' = safePointerFromStackAtLocation c stack
          stacks' =
            ( stackReplaceAtLocationMLStack
                c
                (CodeAddress (cNext code (safePointerFromStackAtLocation c stack)))
                stack,
              us,
              trail
            )
       in ((b, t, c, r, p', up, e, ut, tt, pc, sc, ac), stacks')

-- Return für ML

returnL :: Argument -> RegisterKeller -> RegisterKeller
returnL ATNeg regkeller = returnLNeg regkeller
returnL ATPos regkeller = returnLPos regkeller
returnL _ _ = error "returnL resulted in an error. Possible use of wrong argument."

returnLPos :: RegisterKeller -> RegisterKeller
returnLPos ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  let p' = safePointerFromStackAtLocation (r + 1) stack
      e' = safePointerFromStackAtLocation (r + 2) stack
   in if stackItemAtLocation r stack /= StackAddress Nil
        then
          ( (b, t, c, safePointerFromStackAtLocation r stack + 1, p', up, e', ut, tt, pc, sc, ac),
            (stack, us, trail)
          )
        else ((b, t, c, r, p', up, e', ut, tt, pc, sc, ac), (stack, us, trail))

returnLNeg :: RegisterKeller -> RegisterKeller
returnLNeg ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  ((False, t, c, r, p, up, e, up, tt, pc, sc, ac), (stackWriteToLocation (r - 1) (CodeAddress Nil) stack, us, trail))

-- Backtrack? für GroundL
backtrack :: RegisterKeller -> Zielcode -> RegisterKeller
backtrack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), register@(stack, us, trail)) code
  | b =
    backtrackAfterI
      ( backtrackI
          (safePointerFromStackAtLocation (c + 4) stack) --Hier nicht +1 nachdem der Pointer geholt wurde, da unsere Stacks bei 0 anfangen zu zählen, nicht bei 1
          (backtrackAfterWhile (backtrackWhile all))
      )
      code
  | otherwise = ((b, t, c, r, p + 1, up, e, ut, tt, pc, sc, ac), register)

backtrackIsStackC4Neg :: Pointer -> Bool
backtrackIsStackC4Neg i
  | i < 0 = True
  | otherwise = False

backtrackWhile :: RegisterKeller -> RegisterKeller
backtrackWhile all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail))
  | backtrackCNilRnotNil all =
    backtrackWhile
      ( ( b,
          t,
          safePointerFromStackAtLocation r stack,
          safePointerFromStackAtLocation r stack + 1,
          p,
          up,
          e,
          ut,
          tt,
          pc,
          sc,
          ac
        ),
        stacks
      )
  | otherwise = all

backtrackAfterWhile :: RegisterKeller -> RegisterKeller
backtrackAfterWhile
  ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail)) =
    ((b, safePointerFromStackAtLocation (c + 5) stack, c, r, p, c + 6, safePointerFromStackAtLocation (c + 5) stack + 1, Pointer (-1), tt, 0, sc, Nil), stacks)

backtrackCNilRnotNil :: RegisterKeller -> Bool
backtrackCNilRnotNil ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  safePointerFromStackAtLocation c stack == Nil
    && safePointerFromStackAtLocation r stack /= Nil

backtrackI :: Pointer -> RegisterKeller -> RegisterKeller
backtrackI i all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | i < 0 = all
  | i <= tt = backtrackI (i + 1) (backtrackIIf i all)
  | otherwise = all

backtrackIIf :: Pointer -> RegisterKeller -> RegisterKeller
backtrackIIf i all@(register@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | safePointerFromStackAtLocation i trail <= t =
    let (CodeArg (ATVar symbol add)) = stackItemAtLocation (safePointerFromStackAtLocation i trail) stack
     in (register, (stackReplaceAtLocationMLStack (safePointerFromStackAtLocation i trail) (CodeArg (ATVar symbol Nil)) stack, us, trail))
  | otherwise = all

backtrackAfterI :: RegisterKeller -> Zielcode -> RegisterKeller
backtrackAfterI
  all@(register@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail)) =
    backtrackIfThenElse ((b, t, c, r, p, up, e, ut, safePointerFromStackAtLocation (c + 4) stack, pc, sc, ac), stacks)

backtrackIfThenElse :: RegisterKeller -> Zielcode -> RegisterKeller
backtrackIfThenElse
  all@(register@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail))
  code =
    if safePointerFromStackAtLocation c stack == Nil
      then ((b, t, c, r, cLast code, up, e, ut, tt, pc, sc, ac), stacks)
      else ((False, t, c, r, safePointerFromStackAtLocation c stack, up, e, ut, tt, pc, sc, ac), (backtrackReplace all code, us, trail))

backtrackReplace :: RegisterKeller -> Zielcode -> MLStack
backtrackReplace
  all@(register@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail))
  code =
    stackReplaceAtLocationMLStack c (CodeAddress $ cNext code (safePointerFromStackAtLocation c stack)) stack

-- Prompt für ML

prompt :: RegisterKeller -> Zielcode -> IO ()
prompt ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail)) code
  | b = putStrLn "no (more) solutions"
  | otherwise =
    putStrLn (display stack)
      >> putStrLn "more?"
      >> getLine
      >>= \answer ->
        if answer == ";"
          then
            prompt
              ( auswerten
                  ((True, t, c, r, p -<- 1, up, e, ut, tt, pc, sc, ac), stacks)
                  code
              )
              code
          else print "Wrong input, aborting."

{----------------------------------------------------------------------
  Hilfsfunktionen für ML
 ----------------------------------------------------------------------}

-- Funktion zur Linearisierung von Atomen und Variablen

-- lin(Atom) -> Linearisierung
linearize :: NVLTerm -> [Exp]
linearize atom = linearizeNV atom []

linearizeNV :: NVLTerm -> [Exp] -> [Exp]
linearizeNV (NVLTerm atom subatoms) akk = linearizeV subatoms (akk ++ [ExpLin $ Linearization atom $ length subatoms])

linearizeV :: [LTerm] -> [Exp] -> [Exp]
linearizeV [] akk = akk
linearizeV (LTVar var : rest) akk = linearizeV rest (akk ++ [ExpVar (V var)])
linearizeV (LTNVar atom : rest) akk = linearizeV rest (linearizeNV atom akk)

-- Funktion zum finden einer Kelleradresse
-- TODO Eventuell Problem, siehe Zulip; maybe refactor using takeWhile
-- TODO decide on solution version

sAdd :: RegisterKeller -> Argument -> Argument -> SAddAdd
sAdd rs symbArg mode =
  sAddHandleMode rs symbArg mode (Nil, Pointer 0)

type SAddI = Pointer

type SAddAdd = Pointer

sAddHandleMode ::
  RegisterKeller -> Argument -> Argument -> (SAddAdd, SAddI) -> SAddAdd
sAddHandleMode
  rs@((_, _, c, _, _, _, e, _, _, _, _, _), (stack, _, _))
  symbArg
  mode
  (add, i) =
    case mode of
      ATUnify -> sAddWhile rs symbArg (Nil, e)
      ATPush ->
        if isPNil c
          then Nil
          else sAddWhile rs symbArg (Nil, safePointerFromStackAtLocation (c + 3) stack)
      _ -> error "Unexpected mode in sAdd"

sAddWhile :: RegisterKeller -> Argument -> (SAddAdd, SAddI) -> SAddAdd
sAddWhile (rs, (Stack [], us, trail)) _ _ = Nil
sAddWhile
  rs@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  symArg
  (add, i)
    | not $ isStackAtLocationEndEnv i stack && isPNil add =
      sAddWhileIfStackAtIVarOfSymbol rs (add, i) symArg
    | otherwise = add -- this is debateable but makes function result fit S 147 example

isStackAtLocationEndEnv :: Pointer -> MLStack -> Bool
isStackAtLocationEndEnv _ (Stack []) = False
isStackAtLocationEndEnv i stack = isStackElemEndEnv $ stackItemAtLocation i stack

sAddWhileIfStackAtIVarOfSymbol :: RegisterKeller -> (SAddAdd, SAddI) -> Argument -> SAddAdd
sAddWhileIfStackAtIVarOfSymbol rs@(_, (stack, _, _)) (add, i) arg@(ATVar argSym _) =
  case stackItemAtLocation i stack of
    (CodeArg (ATVar stackSym _)) ->
      if stackSym == argSym then i else sAddWhile rs arg (add, i + 1)
    _ -> sAddWhile rs arg (add, i + 1)
sAddWhileIfStackAtIVarOfSymbol _ _ _ = error "Unexpected call in sAddNewAddIfvar"

-- Dereferenzierungsfunktion; an welchen Term ist Var gebunden

deref :: MLStack -> (Pointer -> Pointer)
deref stack addr =
  case stackItemAtLocation addr stack of
    (CodeArg (ATStr _ _)) -> addr
    stackItemVar@(CodeArg (ATVar _ addr2)) ->
      derefVar stack addr addr2 stackItemVar
    _ -> error "Should have not been reachable: contained neither ATStr or ATVar"

derefVar :: MLStack -> Pointer -> Pointer -> StackElement -> Pointer
derefVar stack addr addr2 stackItemVar =
  if isPNil addr2 then addr else deref stack addr2

-- Aritätsfunktion; gibt Arität eines Atoms zurück

arity :: MLStack -> Pointer -> Arity
arity stack addr =
  case arityHelper (stackItemAtLocation addr stack) of
    Just x -> x
    Nothing -> error "arity was called on non Symbol Element"

arityHelper :: StackElement -> Maybe Arity
arityHelper (CodeArg (ATStr _ arityVal)) = Just arityVal
arityHelper (CodeArg (ATVar _ _)) = Just 0
arityHelper _ = Nothing

-- Displayfunktion für Prompt; untested

display :: MLStack -> String
display stack = displayWhile stack (Pointer 0) ""

displayWhile :: MLStack -> Pointer -> String -> String
displayWhile stack i akk
  | not $ isStackElemEndEnv (stackItemAtLocation i stack) =
    case stackItemAtLocation i stack of
      (CodeArg (ATVar sym add)) ->
        displayWhile
          stack
          (i + 1)
          (displayTerm (deref stack i) stack akk <> " / " <> show sym <> "\n")
      _ -> error "Display while failed because it wasn't an ATVar."
  | otherwise = akk

displayTerm :: Pointer -> MLStack -> String -> String
displayTerm add stack akk = case stackItemAtLocation (deref stack add) stack of
  (CodeArg (ATVar sym p)) ->
    if isPNil p
      then akk <> show sym
      else error "Unexpected ATVar at displayTerm"
  (CodeArg (ATStr sym 0)) -> 
    akk <> show sym 
  (CodeArg (ATStr sym _)) ->
    if add + 1 < Pointer (stackSizeOf stack)
      then displayTerm (deref stack add + 1) stack (concat [akk, show sym, "("]) <> ")"
      else akk <> show sym 
  _ -> "Unexpected display Term call"

isStackElemEndEnv :: StackElement -> Bool
isStackElemEndEnv (CodeArg (ATEndEnv _)) = True
isStackElemEndEnv _ = False

{- isStackElemArg :: Argument -> StackElement -> Bool
isStackElemArg givenarg (CodeArg (arg))
  | arg == givenarg = True
  | otherwise = False
isStackElemArg _ _ = False  -}

{--------------------------------------------------------------------
   Helpers; manually tested; changed for ML.
 --------------------------------------------------------------------}

-- A small explanation for this function:
-- the next "unify" etc is found by doing a string compare.
-- TransformN transforms items of a given stack to strings of length N
transformN :: [Command] -> Int -> Stack String
transformN code amount = Stack (map (take amount . show) code)

cFirst :: Zielcode -> Pointer
cFirst (Stack code) = Pointer $ stackLocationFirstItemOfKind "pushML ATBeg" (transformN code 12)

cNext :: Zielcode -> Pointer -> Pointer
cNext zielcode Nil = Nil
cNext zielcode@(Stack code) p@(Pointer address) =
  case stackLocationFirstItemOfKind' "pushML ATBeg" (transformN (drop (address + 1) code) 12) of
    (Just relativeItemLocation) -> if (p + 1) + Pointer relativeItemLocation == cGoal zielcode then Nil else p + 1 + Pointer relativeItemLocation
    Nothing -> Nil

cLast :: Zielcode -> Pointer
cLast (Stack code) = Pointer $ stackLocationFirstItemOfKind "prompt" (transformN code 6)

cGoal :: Zielcode -> Pointer
cGoal (Stack code) = case stackLocationLastItemOfKind' "return" (transformN code 6) of
  (Just location) -> Pointer location + 1
  Nothing -> Pointer 0

-- the +1 is needed because start of goal is determined by checking the address of the last return statement

{--------------------------------------------------------------------
              ML Unify Hilffunktionen
---------------------------------------------------------------------}
--Makroinstruktionen
addAC :: Int -> RegisterKeller -> RegisterKeller
addAC n all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks) = case ac of
  Pointer i -> ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac +<- n), stacks)
  Nil -> all

restoreAcUpQ :: RegisterKeller -> RegisterKeller
restoreAcUpQ all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail))
  | ac == Pointer 0 = ((b, t, c, r, p, safePointerFromStackAtLocation ut us, e, ut -<- 2, tt, pc, sc, safePointerFromStackAtLocation (ut -<- 1) us), stacks)
  | otherwise = all

saveAcUpQ :: RegisterKeller -> RegisterKeller
saveAcUpQ all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | up <= safePointerFromStackAtLocation (c + 5) stack
      && deref stack up /= up
      && getArity (stackItemAtLocation (deref stack up) stack) /= 0 =
    ( (b, t, c, r, p, deref stack up, e, ut + 2, tt, pc, sc, 1),
      ( stack,
        stackReplaceAtLocationMLStack (ut + 2) (StackAddress up) $ stackReplaceAtLocationMLStack (ut + 1) (StackAddress ac) us,
        trail
      )
    )
  | otherwise = all

{--------------------------------------------------------------------
              ML Unify
---------------------------------------------------------------------}
unify :: Argument -> RegisterKeller -> RegisterKeller
unify arg all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | pc >= 1 = p1 $ unifyPushModus arg all
  | otherwise = p1 $ unifyNonPushModus arg all

unifyPushModus :: Argument -> RegisterKeller -> RegisterKeller
unifyPushModus arg all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = case arg of
  ATVar var add -> ((b, t + 1, c, r, p, up, e, ut, tt, pc -1 + getArity (CodeArg arg), sc, ac), (stackReplaceAtLocationMLStack (t + 1) (CodeArg (ATVar var (sAdd all arg ATUnify))) stack, us, trail))
  ATStr atom ar -> ((b, t + 1, c, r, p, up, e, ut, tt, pc -1 + ar, sc, ac), (stackReplaceAtLocationMLStack (t + 1) (CodeArg arg) stack, us, trail))
  _ -> error "Mitgegebenes Argument für PushModus muss Lineares Atom oder eine Variable sein"

unifyNonPushModus :: Argument -> RegisterKeller -> RegisterKeller
unifyNonPushModus arg all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = case arg of
  (ATVar var add) -> addRestoreUp $ whileSc $ arityUpToSc $ unifyVarNonPIfThenElse arg all
  (ATStr (A str) arity) -> unifyStrNonPIfThenElse arg all
  _ -> error "Mitgegebenes Argument für NonPush-Modus muss Lineares Atom oder eine Variable sein"

-- Hilfsfunktionen für den Fall, dass eine Variable unifiziert werden soll (unifyNonPushModus case arg = ATVar var add)
unifyVarNonPIfThenElse :: Argument -> RegisterKeller -> RegisterKeller
unifyVarNonPIfThenElse arg@(ATVar var add) all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  let (CodeArg arg2@(ATVar symb2 add)) = stackItemAtLocation (deref stack (sAdd all arg ATUnify)) stack
   in if notSameSymbol arg arg2
        then addToStackAndTrailVar arg arg2 all
        else restoreT $ unifyProzedur (deref stack (sAdd all arg ATUnify)) up $ saveT all
unifyVarNonPIfThenElse arg _ = error "Argument has to be ATVar"

arityUpToSc :: RegisterKeller -> RegisterKeller
arityUpToSc all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  ((b, t, c, r, p, up, e, ut, tt, pc, arity stack up, ac), (stack, us, trail))

whileSc :: RegisterKeller -> RegisterKeller
whileSc all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | sc >= 1 = whileSc ((b, t, c, r, p, up + 1, e, ut, tt, pc, sc -1 + arity stack up, ac), (stack, us, trail))
  | otherwise = all

addRestoreUp :: RegisterKeller -> RegisterKeller
addRestoreUp all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  up1 $ restoreAcUpQ $ addAC (-1) all

-- Holt t vom Hilfsstack us zurück
restoreT :: RegisterKeller -> RegisterKeller
restoreT all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = ((b, safePointerFromStackAtLocation ut us, c, r, p, up, e, ut -<- 1, tt, pc, sc, ac), (stack, us, trail))

-- Speichert T in us
saveT :: RegisterKeller -> RegisterKeller
saveT all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = ((b, t, c, r, p, up, e, ut + 1, tt, pc, sc, ac), (stack, stackReplaceAtLocationMLStack (ut + 1) (StackAddress t) us, trail))

notSameSymbol :: Argument -> Argument -> Bool
notSameSymbol arg@(ATVar var add) arg2@(ATVar var2 Nil) = var /= var2
notSameSymbol _ _ = False

addToStackAndTrailVar :: Argument -> Argument -> RegisterKeller -> RegisterKeller
addToStackAndTrailVar
  arg@(ATVar var add)
  arg2@(ATVar var2 add2)
  all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =  
    ( (b, t, c, r, p, up, e, ut, tt + 1, pc, sc, ac),
      ( stackReplaceAtLocationMLStack (deref stack (sAdd all arg ATUnify)) (CodeArg (ATVar var2 up)) stack,
        us,
        stackReplaceAtLocationMLStack (tt + 1) (StackAddress (sAdd all arg ATUnify)) trail
      )
    )
addToStackAndTrailVar _ _ _ = error "War für Variablen gedacht"

--Erhöht up um 1
up1 :: RegisterKeller -> RegisterKeller
up1 ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks) =
  ((b, t, c, r, p, up + 1, e, ut, tt, pc, sc, ac), stacks)

--Erhöht p um 1
p1 :: RegisterKeller -> RegisterKeller
p1 ((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks) =
  ((b, t, c, r, p + 1, up, e, ut, tt, pc, sc, ac), stacks)

--Hilfsfunktionen für den Fall, dass eine structure cell unifiziert werden soll (unifyNonPushModus case arg = ATStr symbol add)
unifyStrNonPIfThenElse :: Argument -> RegisterKeller -> RegisterKeller
unifyStrNonPIfThenElse
  arg@(ATStr (A str) arity)
  all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
    if isVarNil $ getDereferencedUp all
      then addRestoreUp $ addToStackAndTrailStr arg all
      else
        let CodeArg arg2 = getDereferencedUp all
         in checkDereferencedUp arg arg2 all
unifyStrNonPIfThenElse _ _ = error "Diese Funktion soll nur mit Structure cells aufgerufen werden"

isVarNil :: StackElement -> Bool
isVarNil (CodeArg (ATVar symb Nil)) = True
isVarNil _ = False

--Adds the Argument as a Var to the stack and as a Str to the top of stack, adds an address pointing at the dereferenced unification point to the trail, updates the tops of the stacks modiefied and sets the pushcounter to the arity of the pushed cell
addToStackAndTrailStr :: Argument -> RegisterKeller -> RegisterKeller
addToStackAndTrailStr arg@(ATStr (A str) arity) all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  ( (b, t + 1, c, r, p, up, e, ut, tt + 1, arity, sc, ac),
    ( stackReplaceAtLocationMLStack (t + 1) (CodeArg arg) $ stackReplaceAtLocationMLStack (deref stack up) (changePointer (t + 1) $ getDereferencedUp all) stack,
      us,
      stackReplaceAtLocationMLStack (tt + 1) (StackAddress (deref stack up)) trail
    )
  )
addToStackAndTrailStr _ _ = error "addToStackAndTrailStr soll nur mit ATStr Argumenten aufgerufen werden"

getDereferencedUp :: RegisterKeller -> StackElement
getDereferencedUp all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = stackItemAtLocation (deref stack up) stack

changePointer :: Pointer -> StackElement -> StackElement
changePointer pointer (CodeArg (ATVar var _)) = CodeArg (ATVar var pointer)
changePointer _ _ = error "Nur ATVar Elemente im Stack haben Pointer die geändert werden können"

checkDereferencedUp :: Argument -> Argument -> RegisterKeller -> RegisterKeller
checkDereferencedUp arg@(ATStr symb arity) arg2@(ATStr symb2 arity2) all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks@(stack, us, trail)) =
  if symb /= symb2 || arity /= arity2
    then ((True, t, c, r, p, up, e, ut, tt, pc, sc, ac), stacks)
    else up1 $ restoreAcUpQ $ addAC (arity - 1) $ saveAcUpQ all
checkDereferencedUp _ _ _ = error "This function checks if the unification of two cells was unsuccesful"

--to get the Arity of the to be unified Argument in push mode
getArity :: StackElement -> Int
getArity (CodeArg (ATStr _ arity)) = arity
getArity (CodeArg (ATVar _ _)) = 0
getArity _ = error "What"

--TODO unify Prozedur, setzt b im Endeffekt
unifyProzedur :: Pointer -> Up -> RegisterKeller -> RegisterKeller
unifyProzedur add1 add2 all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = unifyProzedur' True (stackPush (StackAddress add2) $ stackPush (StackAddress add1) stack) all

unifyProzedur' :: Bool -> MLStack -> RegisterKeller -> RegisterKeller
unifyProzedur' weiter hilfsstack all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  if weiter && not (stackEmpty hilfsstack) && stackSizeOf hilfsstack > stackSizeOf stack
    then check2Unify (getD (stackPeekTop hilfsstack) hilfsstack) (getD (stackPeekTop (stackPop hilfsstack)) hilfsstack) weiter (stackPop $ stackPop hilfsstack) all
    else ((not weiter, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))

--Holt die dereferenierte Adresse des StackElementes
getD :: StackElement -> MLStack -> Pointer
getD (CodeAddress pointer) stack = deref stack pointer
getD (StackAddress pointer) stack = deref stack pointer
getD (TrailAddress pointer) stack = deref stack pointer
getD (UsAddress pointer) stack = deref stack pointer
getD (CodeArg (ATVar _ Nil)) _ = Nil
getD (CodeArg (ATVar _ pointer)) stack = deref stack pointer
getD (CodeArg _) _ = Nil

check2Unify :: Pointer -> Pointer -> Bool -> MLStack -> RegisterKeller -> RegisterKeller
check2Unify d1 d2 weiter hilfsstack all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = 
  if d1 /= d2
    then
      let arg = stackItemAtLocation d1 stack
       in check2UnifyIf arg d1 d2 weiter hilfsstack all
    else unifyProzedur' weiter hilfsstack all

check2UnifyIf :: StackElement -> Pointer -> Pointer -> Bool -> MLStack -> RegisterKeller -> RegisterKeller
check2UnifyIf arg@(CodeArg (ATVar var Nil)) d1 d2 weiter hilfsstack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) = 
    ((not weiter, t, c, r, p, up, e, ut, tt + 1, pc, sc, ac),
      ( stackReplaceAtLocationMLStack d1 (CodeArg (ATVar var d2)) stack,
        us,
        stackReplaceAtLocationMLStack (tt + 1) (StackAddress d1) trail
      ))
check2UnifyIf _ d1 d2 weiter hilfsstack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  let arg2 = stackItemAtLocation d2 stack
   in check3UnifyIf arg2 d1 d2 weiter hilfsstack all

check3UnifyIf :: StackElement -> Pointer -> Pointer -> Bool -> MLStack -> RegisterKeller -> RegisterKeller
check3UnifyIf arg2@(CodeArg (ATVar var2 Nil)) d1 d2 weiter hilfsstack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  ( (not weiter, t, c, r, p, up, e, ut, tt + 1, pc, sc, ac),
    ( stackReplaceAtLocationMLStack d1 (CodeArg (ATVar var2 d1)) stack,
      us,
      stackReplaceAtLocationMLStack (tt + 1) (StackAddress d2) trail
    )
  )
check3UnifyIf _ d1 d2 weiter hilfsstack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  let (arg@(CodeArg (ATStr symb arity)), arg2@(CodeArg (ATStr symb2 arity2))) = (stackItemAtLocation d1 hilfsstack, stackItemAtLocation d2 hilfsstack)
   in checkForUnify (arg, arg2) d1 d2 weiter hilfsstack all

checkForUnify :: (StackElement, StackElement) -> Pointer -> Pointer -> Bool -> MLStack -> RegisterKeller -> RegisterKeller
checkForUnify (arg@(CodeArg (ATStr symb arity)), arg2@(CodeArg (ATStr symb2 arity2))) d1 d2 weiter hilfsstack all@((b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail)) =
  if symb /= symb2 || arity /= arity2
    then unifyProzedur' False hilfsstack all
    else pushD1D2 d1 d2 1 arity weiter hilfsstack all
checkForUnify _ _ _ _ _ _ =
  error "checkForUnify is suppossed to be called with two structure cells"

pushD1D2 :: Pointer -> Pointer -> Int -> Arity -> Bool -> MLStack -> RegisterKeller -> RegisterKeller
pushD1D2 d1 d2 i arity weiter hilfsstack all@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  | i <= arity =
    pushD1D2
      d1
      d2
      (i + 1)
      arity
      weiter
      (stackPush (StackAddress (d2 +<- i)) $ stackPush (StackAddress (d1 +<- i)) hilfsstack)
      all
  | otherwise = unifyProzedur' weiter hilfsstack all

{--------------------------------------------------------------------
              ML Auswertung
---------------------------------------------------------------------}

--Die Logik dahinter: Man lässt die Befehle durchlaufen und müsste dann bei einem korrekten Programm am Ende bei Prompt gelandet sein.
--Dann könnte man in der Main Methode prompt aufrufen und abhängig vom Resultat noch einmal auswertung aufrufen, aber eben mit den in Prompt angepassten werten.
--Hoffe das geht so,
auswerten :: RegisterKeller -> Zielcode -> RegisterKeller
auswerten
  rs@(addressreg@(b, t, c, r, p, up, e, ut, tt, pc, sc, ac), (stack, us, trail))
  code = 
    let cmd = stackItemAtLocation (pToInt p) code
     in ( if Prompt prompt == cmd
            then rs
            else auswerten (executeCommand cmd rs code) code
        )

-- Execute command on register stack
executeCommand :: Command -> (RegisterKeller -> (Zielcode -> RegisterKeller))
executeCommand cmd rs code = case cmd of
  Unify unify args -> unify args rs
  Push push args -> push args rs code
  Call call -> call rs code
  Return returnL args -> returnL args rs
  Backtrack backtrack -> backtrack rs code
  Prompt prompt -> rs

initRegstack :: Zielcode -> RegisterKeller
initRegstack code =
  ( (False, Pointer (-1), Nil, Nil, cGoal code, Nil, Nil, Pointer (-1), Pointer (-1), 0, 0, Nil),
    (Stack [], Stack [], Stack [])
  )

promptWasCalled :: Zielcode -> RegisterKeller
promptWasCalled code = auswerten (initRegstack code) code
