{-# LANGUAGE LambdaCase #-}
import Distribution.Fields (ParseResult)
import Control.Applicative (Alternative, empty, (<|>), many, some)
import Control.Monad (void)
import Data.Char (isNumber, isAlpha, isAlphaNum)
import Data.Map (Map, insert, lookup, empty)
import System.Environment (getArgs)
import GHC.IO.FD (openFile)
import qualified Control.Applicative as Applicative
import qualified Control.Applicative as Map

newtype Parser i r = Parser { run :: [i] -> Maybe ([i], r)}
instance Functor (Parser i) where
    fmap :: (r1 -> r2) -> Parser i r1 -> Parser i r2
    fmap f (Parser p) = Parser $ \input -> do
        (input', r) <- p input
        return (input', f r)
instance Applicative (Parser i) where
    pure :: a -> Parser i a
    pure a = Parser (\input -> Just (input, a))
    (<*>) :: Parser i (a -> b) -> Parser i a -> Parser i b
    (Parser f) <*> (Parser a) = Parser $ \input -> do
        (input', ff) <- f input
        (input'', aa) <- a input'
        return (input'', ff aa)
instance Alternative (Parser i) where
    empty = Parser $ const Applicative.empty
    (Parser p1) <|> (Parser p2) = Parser $ \input -> p1 input <|> p2 input
type StringParser = Parser Char
charPredP :: (Char -> Bool) -> StringParser Char
charPredP pred = Parser (\case
        x:xs -> if pred x then Just (xs, x) else Nothing
        _ -> Nothing)
stringPredP :: (Char -> Bool) -> StringParser String
stringPredP pred = many $ charPredP pred
charP :: Char -> StringParser Char
charP c = charPredP (==c)
stringP :: String -> StringParser String
stringP = traverse charP

data MultiplicativeOp = MulOp | DivOp
    deriving (Show, Eq)
data AdditiveOp = PlusOp | MinusOp
    deriving (Show, Eq)
type Iden = String
data Token = AddOpTok AdditiveOp | MulOpTok MultiplicativeOp | Assign | Equal | Lparen | Rparen | IntTok Int | IdenTok Iden
    deriving (Show, Eq)
type TokenParser = Parser Token

type Expr = AddExpr
data AddExpr =  AddExpr MulExpr [(AdditiveOp, MulExpr)]
    deriving (Show, Eq)
data MulExpr = MulExpr PrimaryExpr [(MultiplicativeOp, PrimaryExpr)]
    deriving (Show, Eq)
data PrimaryExpr = IntExpr Int | VarExpr Iden | ParenExpr Expr
    deriving (Show, Eq)

data Statement = VarDefSta Iden Expr | EvalSta Expr
    deriving (Show, Eq)
ws :: StringParser ()
ws = void $ many $ charP ' ' <|> charP '\t' <|> charP '\n'


intTokP :: StringParser Token
intTokP = IntTok . read <$> some (charPredP isNumber)
idenTokP :: StringParser Token
idenTokP = IdenTok <$> ((:) <$> charPredP isAlpha <*> many (charPredP isAlphaNum) )

tokenP =
    ws *>
    (
        AddOpTok PlusOp <$ charP '+' <|>
        AddOpTok MinusOp <$ charP '-' <|>
        MulOpTok MulOp <$ charP '*' <|>
        MulOpTok DivOp <$ charP '/' <|>
        Assign <$ stringP ":=" <|>
        Equal <$ charP '=' <|>
        Lparen <$ charP '(' <|>
        Rparen <$ charP ')' <|>
        intTokP <|>
        idenTokP
    )
-- intexprP :: TokenParser Expr
-- intexprP = Parser $ \case
--     (IntTok i):xs -> Just (xs, IntExpr i)
--     _ -> Nothing
-- binopExpr :: TokenParser Expr
-- binopExpr = Parser $ \ 
tokensP = many $ tokenP <* ws
idP :: Eq r => r -> Parser r r
idP t = Parser $ \case
    x:xs -> if t == x then Just (xs, t) else Nothing
    _ -> Nothing
pExprP :: TokenParser PrimaryExpr
mulExprP :: TokenParser MulExpr
addExprP :: TokenParser AddExpr
exprP :: TokenParser Expr
pExprP = 
    Parser (\case
    (IntTok i):xs -> Just (xs, IntExpr i)
    (IdenTok s):xs -> Just (xs, VarExpr s)
    _ -> Nothing) <|> 
    ParenExpr <$> (idP Lparen *> exprP <* idP Rparen)

mulExprP = MulExpr <$> pExprP <*> many rest
    where
        rest :: TokenParser (MultiplicativeOp, PrimaryExpr)
        op = Parser $ \case
            (MulOpTok i):xs -> Just (xs, i)
            _ -> Nothing
        rest = (,) <$> op <*> pExprP
addExprP = AddExpr <$> mulExprP <*> many rest
    where
        rest :: TokenParser (AdditiveOp, MulExpr)
        op = Parser $ \case
            (AddOpTok i):xs -> Just (xs, i)
            _ -> Nothing
        rest = (,) <$> op <*> mulExprP
exprP = addExprP

type Closure = Map Iden Expr
evalExpr :: Expr -> Closure-> Float
evalAddExpr :: AddExpr -> Closure -> Float
evalMulExpr :: MulExpr -> Closure-> Float
evalPrimaryExpr :: PrimaryExpr -> Closure -> Float

evalExpr = evalAddExpr
evalAddExpr (AddExpr e es) c = evalList (evalMulExpr e c) es c
    where
        evalList acc [] c = acc
        evalList acc ((PlusOp, e):es) c   = evalList (acc + evalMulExpr e c) es c
        evalList acc ((MinusOp, e):es) c = evalList (acc - evalMulExpr e c) es c

evalMulExpr (MulExpr e es) c = evalList (evalPrimaryExpr e c) es c
    where
        evalList acc [] c = acc
        evalList acc ((MulOp, e):es) c  = evalList (acc * evalPrimaryExpr e c) es c
        evalList acc ((DivOp, e):es) c   = evalList (acc / evalPrimaryExpr e c) es c
evalPrimaryExpr (IntExpr i) c     = fromIntegral i
evalPrimaryExpr (ParenExpr e) c   = evalExpr e c
evalPrimaryExpr (VarExpr name) c = evalExpr e c
    where Just e = Data.Map.lookup name c 


staP :: TokenParser Statement
varDefStaP :: TokenParser Statement
evalStaP :: TokenParser Statement
varDefStaP = VarDefSta <$> (idenP <* idP Assign) <*> exprP
    where 
        idenP = Parser $ \case
            (IdenTok s):xs -> Just (xs, s)
            _ -> Nothing 
evalStaP = EvalSta <$> exprP <* idP Equal
staP = varDefStaP <|> evalStaP
stasP :: Parser Token [Statement]
stasP = many staP

runSta :: [Statement] -> IO ()
runSta stas = snd $ runSta' (Data.Map.empty, pure ()) stas 
    where
        f :: (Closure, IO ()) -> Statement -> (Closure, IO ())
        f (c, io) (VarDefSta name expr)  = (insert name expr c, io)
        f (c, io) (EvalSta expr)         = (c, io >>= const (print $ evalExpr expr c))
        runSta' :: (Closure, IO ()) -> [Statement] -> (Closure, IO ())
        runSta' = Prelude.foldl f




test :: IO ()
test = do
    print expr_res
    print sta_res
    where 
        expr_res = do
            (_, tokens) <- run tokensP "(3 + 4) * 2 - 10 / 2"
            (_, expr) <- run exprP tokens
            return $ evalExpr expr Data.Map.empty
        sta_res = do 
            (_, tokens) <- run tokensP "a := 5"
            (_, sta) <- run staP tokens
            return sta


main :: IO ()
main = do
    file_path:_ <- getArgs
    file_content <- readFile file_path
    let Just stas = do
            (_, tokens) <- run tokensP file_content
            (_, stas) <- run stasP tokens
            return stas
    runSta stas
    return ()


        
        





