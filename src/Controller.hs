{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric  #-}
{-# LANGUAGE DeriveAnyClass #-}

module Controller where
import Finance
import Network.Wai
import Network.Wai.Handler.Warp
import Servant
import System.IO
import Database.PostgreSQL.Simple
import Text.Printf
import GHC.Generics
import Data.Aeson
import Data.Scientific
import Data.Maybe

data Report = Report
    {debits :: Scientific,
    credits :: Scientific,
    totals  :: Scientific,
    transactionCount :: Int,
    accountCount :: Int,
    transactionOutstandingCount :: Int,
    transactionFutureCount :: Int,
    creditCount :: Int,
    debitCount :: Int,
    reoccurringCount :: Int,
    categoryCount :: Int
    } deriving (Show, Eq, Generic, ToJSON, FromJSON)

-- curl 'http://localhost:3000/'
-- curl 'http://localhost:3000/transaction'
-- curl 'http://localhost:3000/transaction/1001'
-- curl 'http://localhost:3000/report'
-- curl 'http://localhost:3000/optional?parm1=5'
type TransactionApi =
  Get '[JSON] String
  :<|> "transaction" :> Get '[JSON] [Transaction]
  :<|> "transaction" :> Capture "id" Integer :> Get '[JSON] Transaction
  :<|> "report" :> Get '[JSON] Report
--  :<|> "optional" :> Get '[JSON] String
  :<|> "optional" :> QueryParam "parm1" Int :> Get '[JSON] String  -- equivalent to 'GET /optional?parm1=test'
                       
transactionApi :: Proxy TransactionApi
transactionApi = Proxy

apiService :: IO ()
apiService = do
  let port = 3000
  let settings =  setPort port $ setBeforeMainLoop (hPutStrLn stderr ("listening on port " ++ show port)) defaultSettings
  runSettings settings =<< mkApp

mkApp :: IO Application
mkApp = do
    connection <- connect defaultConnectInfo { connectHost = "192.168.100.124", connectDatabase = "finance_db", connectUser = "henninb", connectPassword = "monday1"}
    transactions <- selectAllTransactions connection
    accounts <- selectAllAccounts connection
    let credits = transactionCredits transactions
    let debits = transactionDebits transactions
    let reoccurring = transactionsReoccurring transactions
    let categoriesList = extractCategories transactions
    let categoriesCount = sortAndGroupByList categoriesList

--    printf "Transaction Quantity: %d\n" (length transactions)
--    printf "Account Quantity: %d\n" (length accounts)
--    printf "Transactions Outstanding: %d\n" (length (outstandingTransactions transactions))
--    printf "Transactions Future: %d\n" (length (futureTransactions transactions))
--    printf "Credits Quantity: %d\n"  (length credits)
--    printf "Debits Quantity: %d\n" (length debits)
--    printf "Reoccurring Quantity: %d\n" (length reoccurring)
--    printf "Category Quantity: %d\n" (length categoriesCount)
    return $ serve transactionApi (server transactions accounts)

server :: [Transaction] -> [Account] -> Server TransactionApi
server transactions accounts =
  getRoot
  :<|> getTransactions transactions
  :<|> getTransactionById transactions
  :<|> getReport transactions
  :<|> getParm

getTransactions :: [Transaction] -> Handler [Transaction]
getTransactions = return

-- http://localhost:3000/transaction/1001
getTransactionById :: [Transaction] -> Integer -> Handler Transaction
getTransactionById transactions x = return (fromJustCustom (findByTransactionId x transactions))
--getTransactionById _ _ = throwError err404

getRoot :: Handler String
getRoot = return "{}"



getReport :: [Transaction] -> Handler Report
getReport transactions = return report
  where
    credits = transactionCredits transactions
    debits = transactionDebits transactions
    transactionCount = length transactions
    transactionOutstandingCount = length (outstandingTransactions transactions)
    transactionFutureCount = length (futureTransactions transactions)
    creditCount = length credits
    debitCount = length debits
    reoccurringCount = length (transactionsReoccurring transactions)
    report = Report (sumOfActiveTransactions debits)
                    (sumOfActiveTransactions credits) (sumOfActiveTransactions debits - sumOfActiveTransactions credits)
                    transactionCount 0 transactionOutstandingCount transactionFutureCount creditCount debitCount reoccurringCount 0

fromJustCustom :: Maybe a -> a
fromJustCustom Nothing = error "Maybe.fromJust: Nothing"
fromJustCustom (Just x) = x

--getParm :: Maybe Int -> Handler String
--getParm i = return (show (fromJustCustom i))

getParm :: Maybe Int -> Handler String
getParm parm = return result
  where
  parm1 = fromMaybe 0 parm
  result = if parm1 == 0 then "failure" else show parm1

--stringHandler = liftIO ioMaybeString >>= f
--    where f (Just str) = return str
--          f Nothing = throwError err404