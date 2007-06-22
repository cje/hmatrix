{-# OPTIONS_GHC -fglasgow-exts #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Packed.Internal.Vector
-- Copyright   :  (c) Alberto Ruiz 2007
-- License     :  GPL-style
--
-- Maintainer  :  Alberto Ruiz <aruiz@um.es>
-- Stability   :  provisional
-- Portability :  portable (uses FFI)
--
-- Vector implementation
--
-----------------------------------------------------------------------------

module Data.Packed.Internal.Vector where

import Data.Packed.Internal.Common
import Foreign
import Complex
import Control.Monad(when)

type Vc t s = Int -> Ptr t -> s
-- not yet admitted by my haddock version
-- infixr 5 :>
-- type t :> s = Vc t s

vec :: Vector t -> (Vc t s) -> s
vec v f = f (dim v) (ptr v)

baseOf v = (v `at` 0)

createVector :: Storable a => Int -> IO (Vector a)
createVector n = do
    when (n <= 0) $ error ("trying to createVector of dim "++show n)
    fp <- mallocForeignPtrArray n
    let p = unsafeForeignPtrToPtr fp
    --putStrLn ("\n---------> V"++show n)
    return $ V n fp p

fromList :: Storable a => [a] -> Vector a
fromList l = unsafePerformIO $ do
    v <- createVector (length l)
    let f _ p = pokeArray p l >> return 0
    f // vec v // check "fromList" []
    return v

toList :: Storable a => Vector a -> [a]
toList v = unsafePerformIO $ peekArray (dim v) (ptr v)

n # l = if length l == n then fromList l else error "# with wrong size"

at' :: Storable a => Vector a -> Int -> a
at' v n = unsafePerformIO $ peekElemOff (ptr v) n

at :: Storable a => Vector a -> Int -> a
at v n | n >= 0 && n < dim v = at' v n
       | otherwise          = error "vector index out of range"

instance (Show a, Storable a) => (Show (Vector a)) where
    show v = (show (dim v))++" # " ++ show (toList v)

-- | creates a Vector taking a number of consecutive toList from another Vector
subVector :: Storable t => Int       -- ^ index of the starting element
                        -> Int       -- ^ number of toList to extract
                        -> Vector t  -- ^ source
                        -> Vector t  -- ^ result
subVector k l (v@V {dim=n, ptr=p, fptr=fp})
    | k<0 || k >= n || k+l > n || l < 0 = error "subVector out of range"
    | otherwise = unsafePerformIO $ do
        r <- createVector l
        let f = copyArray (ptr r) (advancePtr p k) l >> return 0
        f // check "subVector" [v]
        return r

subVector' k l (v@V {dim=n, ptr=p, fptr=fp})
    | k<0 || k >= n || k+l > n || l < 0 = error "subVector out of range"
    | otherwise = v {dim=l, ptr=advancePtr p k}



-- | creates a new Vector by joining a list of Vectors
join :: Field t => [Vector t] -> Vector t
join [] = error "joining zero vectors"
join as = unsafePerformIO $ do
    let tot = sum (map dim as)
    r@V {fptr = p, ptr = p'} <- createVector tot
    withForeignPtr p $ \_ ->
        joiner as tot p'
    return r
  where joiner [] _ _ = return ()
        joiner (V {dim = n, fptr = b, ptr = q} : cs) _ p = do
            withForeignPtr b  $ \_ -> copyArray p q n
            joiner cs 0 (advancePtr p n)


-- | transforms a complex vector into a real vector with alternating real and imaginary parts 
asReal :: Vector (Complex Double) -> Vector Double
asReal v = V { dim = 2*dim v, fptr =  castForeignPtr (fptr v), ptr = castPtr (ptr v) }

-- | transforms a real vector into a complex vector with alternating real and imaginary parts
asComplex :: Vector Double -> Vector (Complex Double)
asComplex v = V { dim = dim v `div` 2, fptr =  castForeignPtr (fptr v), ptr = castPtr (ptr v) }


constantG n x = fromList (replicate n x)

constantR :: Int -> Double -> Vector Double
constantR = constantAux cconstantR

constantC :: Int -> Complex Double -> Vector (Complex Double)
constantC = constantAux cconstantC

constantAux fun n x = unsafePerformIO $ do
    v <- createVector n
    px <- newArray [x]
    fun px // vec v // check "constantAux" []
    free px
    return v

foreign import ccall safe "aux.h constantR"
    cconstantR :: Ptr Double -> TV -- Double :> IO Int

foreign import ccall safe "aux.h constantC"
    cconstantC :: Ptr (Complex Double) -> TCV -- Complex Double :> IO Int

constant :: Field a => Int -> a -> Vector a
constant n x | isReal id x = scast $ constantR n (scast x)
             | isComp id x = scast $ constantC n (scast x)
             | otherwise   = constantG n x

