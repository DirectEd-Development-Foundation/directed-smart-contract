{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module VerifiedByToken where

import           PlutusTx.Prelude       hiding (Semigroup(..), unless)
import Plutus.V2.Ledger.Api as PlutusV2
import PlutusTx (compile, liftCode, applyCode)
import Utilities ( wrapMintingPolicy, scriptCurrencySymbol )
import Plutus.V1.Ledger.Value (flattenValue, valueOf)
import Plutus.V2.Ledger.Contexts (txSignedBy)
import Plutus.V1.Ledger.Address (toPubKeyHash)


--This minting policy requires that the transaction is signed by the minting institution, and that the token is sent to the pkh specified in the tokenName. Burning is always allowed.
--We check the scriptPurpose in order to find the currencySymbol of this script. Then we demand that all minting done with this currencySymbol must either be a burn or signed and sent to specified pkh.
{-# INLINABLE mkPolicy #-}
mkPolicy :: PubKeyHash -> () -> ScriptContext -> Bool
mkPolicy instPkh () ctx = all (\(_,tn,n) -> (n<0) || (n>0 && traceIfFalse "not signed by institution" signedByInstitution &&
                                               traceIfFalse "must send to specified pkh" (sentToNamedWallet tn) )
                                        ) tokensFromScript
  where
    txInfo = scriptContextTxInfo ctx
    txOuts = txInfoOutputs txInfo
    Minting curSym = scriptContextPurpose ctx
    tokensFromScript = filter (\(c,_,_)->c==curSym) (flattenValue $ txInfoMint txInfo)
    signedByInstitution = txSignedBy txInfo instPkh
    maybePkhReciever tn = find (\txOut -> valueOf (txOutValue txOut) curSym tn > 0) txOuts >>= toPubKeyHash . txOutAddress
    sentToNamedWallet tn = maybe False ((==) (unTokenName tn) . getPubKeyHash) (maybePkhReciever tn)
    

{-# INLINABLE mkWrappedPolicy #-}
mkWrappedPolicy :: PubKeyHash -> BuiltinData -> BuiltinData -> ()
mkWrappedPolicy = wrapMintingPolicy . mkPolicy

policy :: PubKeyHash -> MintingPolicy
policy pkh = mkMintingPolicyScript ($$(compile [|| mkWrappedPolicy ||]) `applyCode` liftCode pkh)

{-# INLINABLE curSymbol #-}
curSymbol :: PubKeyHash -> CurrencySymbol
curSymbol = scriptCurrencySymbol . policy