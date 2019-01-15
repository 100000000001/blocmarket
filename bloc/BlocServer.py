# Data imports
import numpy as np
import numpy.matlib as npm
import pandas as pd
from sqlalchemy import create_engine, Table, Column, Integer, Boolean, String, Float, \
    LargeBinary, BLOB, MetaData, update, ForeignKey
import os, platform

# Crypto imports
import nacl.encoding
import nacl.signing

# Other imports
import itertools




class BlocServer(object):

    def __init__(self):

        # self.engine = create_engine('sqlite:///:memory:', echo=True)
        # self.engine = create_engine("postgresql://alpine:3141592@localhost/blocparty",
        #                              isolation_level="AUTOCOMMIT")
        # Note postgress needs AUTOCOMMIT or else postgress hangs when it gets to a matching trade
        # DATABASE_URL = 'sqlite:///pmarket.db'
        # DATABASE_URL = 'postgresql://vzpupvzqyhznrh:14eeeb882d30a816ad01f3fe64610f3a9e465d2158821cf003b08f1169f3a786@ec2-54-83-8-246.compute-1.amazonaws.com:5432/dbee8j5ki95jfn'

        if platform.system() == 'Darwin':
            # Use local postgres if on mac
            DATABASE_URL = "postgresql://alpine:3141592@localhost/blocparty"
        else:
            # Use DATABASE_URL from env otherwise
            DATABASE_URL = os.environ['DATABASE_URL']

        self.engine = create_engine(DATABASE_URL, isolation_level="AUTOCOMMIT")
        self.engine.echo = False
        self.metadata = MetaData(self.engine)
        self.userTable = Table('userTable', self.metadata,
                               Column('traderId', Integer, primary_key=True),
                               Column('verifyKey', String),
                               )
        # Order book for all trades, including including order book,
        # matched, and linked trades (offsets, partials, etc)
        self.orderBook = Table('orderBook', self.metadata,
                               Column('tradeId', Integer, primary_key=True, autoincrement=True),
                               Column('price', Float),
                               Column('quantity', Float),
                               #Column('marketRootId', Integer),
                               #Column('marketBranchId', Integer),
                               Column('marketId', Integer),
                               Column('traderId', Integer,),
                               Column('signature', LargeBinary),
                               Column('iMatched', Boolean),
                               Column('iRemoved', Boolean),
                               )

        # Market table with minimum and maximum of each market.
        self.marketTable = Table('marketTable', self.metadata,
                                 Column('marketRootId', Integer),
                                 Column('marketBranchId', Integer),
                                 Column('marketId', Integer),
                                 Column('marketMin', Float),
                                 Column('marketMax', Float),
                                 Column('traderId', Integer),
                                 Column('signature', LargeBinary),
                                 )

        # Possible combinations of root market outcomes
        self.marketBounds = Table('marketBounds', self.metadata,
                                  Column('marketBounds', Integer),
                                  Column('marketRootId', Integer),
                                  Column('marketBranchId', Integer),
                                  Column('marketMin', Float),
                                  Column('marketMax', Float),
                                  )

        # Market state (possible combinations)
        self.outcomeCombinations = Table('outcomeCombinations', self.metadata,
                                         Column('outcomeId', Integer, primary_key=True),
                                         Column('marketRootId', Integer),
                                         Column('marketBranchId', Integer),
                                         Column('marketMin', Float),
                                         Column('marketMax', Float),
                                         )

        # Create all tables
        self.metadata.create_all(self.engine)
        self.conn = self.engine.connect()

        # Collateral limit
        self.COLLATERAL_LIMIT = 2

        # Temporary local variables
        self.marketOutcomes = np.array([])  # Market corners
        self.p = np.array([0])
        self.q = np.array([0])
        self.mInd = np.array([0])
        self.tInd = np.array([0])
        self.iMatched = np.array([False])
        self.sig = np.array([0])

    def purgeTables(self):
        """ Purge all tables before starting a test. """
        self.userTable.delete().execute()
        self.orderBook.delete().execute()
        self.marketTable.delete().execute()
        self.marketBounds.delete().execute()
        self.outcomeCombinations.delete().execute()
        print("All tables deleted.")

    def purgeNonUserTables(self):
        """ Purge all tables before starting a test"""
        self.orderBook.delete().execute()
        self.marketTable.delete().execute()
        self.marketBounds.delete().execute()
        self.outcomeCombinations.delete().execute()
        print("All tables except userTable deleted.")


    # Basic API:
    # createUser
    # createMarket
    # createTrade

    def createUser(self, verifyKey_hex: str) -> object:

            """ Create a new user and adds to userTable.

            :param verifyKey_hex: (str) verify key
            :return newUsrRow: (DataFrame) new user row
            :return self.userTable: (sql table) new row of userTable

            :Example:

            bs = BlocServer()
            bs.createUser('8d708ff647f671b29709a39c5f1529b06d6841fa268f03a834ebf6aad5e6d8e4')

            :Example:

            bc = BlocClient()
            bc.generateSignatureKeys
            bs = BlocServer()
            bs.createUser(bc.verifyKey_hex)

            .. note::
            - Verify key constructed with BlocClient.generateSignatureKeys()
            - Successful call adds new column to userTable.

            .. todo:: check that this is a valid key.
            """

            # Check if this key is already in userTable
            userTable = pd.read_sql_query('SELECT * FROM "userTable" WHERE "verifyKey" = \'%s\'' % (verifyKey_hex), self.conn)
            if not userTable.empty:
                print('Username already exists, sorry buddy.')
                return False
            else:
                traderId = len(pd.read_sql_table("userTable", self.conn)) + 1
                # Create the new user
                newUsr = dict(verifyKey=verifyKey_hex, traderId=int(traderId))
                # Insert to usertable (autoincrements traderId)
                self.conn.execute(self.userTable.insert(), [newUsr, ])
                # Pull back row to get traderID
                newUsrRow = pd.read_sql_query('SELECT * FROM "userTable" WHERE "verifyKey" = \'%s\'' % (verifyKey_hex),
                                              self.conn)

            # Return new user
            return newUsrRow.loc[0].to_dict()

    def createMarket(self, marketRootId, marketBranchId, marketMin, marketMax, traderId, previousSig, signature, verifyKey) -> bool:
            """
            Create a new row in marketTable. Update existing market
            with new bounds if market already exists.

            :param marketRootId
            :param marketBranchId
            :param marketMin
            :param marketMax
            :param traderId
            :param previousSig
            :param signature
            :param verifyKey
            marketMax, marketRootId, marketBranchId, previousSignature,
            signatureMsg, signature]
            :return checks: (boolean) - True if checks pass
            :return self.marketTable: - new row in market table
            :return self.outputCombinations: - updated output combinations  table
            :return: self.marketBounds: - updated market bounds

            :Example:

            .. todo:: Example
            .. todo:: Input check for valid key
            .. todo:: Some kind of informative output
            """

            mT = pd.read_sql_table('marketTable', self.conn)

            # If the market exists, use previous Id
            marketId = (mT[(mT['marketRootId'] == marketRootId) & (mT['marketBranchId'] == marketBranchId)]['marketId']).unique()

            # Create market id
            if mT.empty:
                marketId = 1
            elif marketId.size ==0:
                marketId = mT['marketId'].max()+1
            else:
                marketId = marketId[0]


            newMarket = pd.DataFrame({'marketId': [marketId],
                                       'marketRootId': [marketRootId],
                                       'marketBranchId': [marketBranchId],
                                       'marketMin': [marketMin],
                                       'marketMax': [marketMax],
                                       'traderId': [traderId],
                                       'signature': signature})

            # Check signature chain for market
            chainChk = False
            if mT.empty:
                # If there are no existing markets chain is ok
                chainChk = True
            else:
                # Check that the previous sig of new market is the sig of the
                # previous market
                prevMarket = self.getPreviousMarket()
                chainChk = bytes(prevMarket['signature'][0]) == previousSig

            # If market exists...
            matchCurrentMarket = pd.merge(left=mT, right=newMarket, on=['marketRootId', 'marketBranchId'])
            ownerChk = True
            if not matchCurrentMarket.empty:
                # Check that trader owns it
                ownerChk = matchCurrentMarket.loc[0, 'traderId_x'] == matchCurrentMarket.loc[0, 'traderId_y']

            # Verify market signature is valid
            sigMsg = \
                str(marketRootId).encode("utf-8") + \
                str(marketBranchId).encode("utf-8") + \
                str(marketMin).encode("utf-8") + \
                str(marketMax).encode("utf-8") + \
                str(traderId).encode("utf-8") + \
                previousSig + b'end'

            sigChk = self.checkSignature(signature, sigMsg, verifyKey)

            # Convert sigChk to logical
            if isinstance(sigChk, bytes):
                sigChk = True
            # Check market range
            marketRangeChk = newMarket.loc[0, 'marketMin'] <= newMarket.loc[0, 'marketMax']
            # Checks (correct market number, signature relative to parent, range)
            checks = marketRangeChk and sigChk and chainChk and ownerChk

            #  Add market to table if checks pass
            if checks:
                newMarket.to_sql(name='marketTable', con=self.conn, if_exists='append', index=False)
                # Update all possible combinations of root markets
                self.updateOutcomeCombinations()
            else:
                print('Signature does not match, bad signature chain, or else marketMin > marketMax. Market not added.')

            # Return True if checks pass and market added
            return checks

    def createTrade(self, p_, q_, mInd_, tInd_, previousSig, signature, verifyKey)->bool:

        """
        Create a new row in marketTable. Update existing market with new bounds if market already exists.

        :param p_: price
        :param q_: quantity
        :param mInd_: market index
        :param tInd_: trader index
        :param previousSig: Previous signature
        :param signature: Signature
        :param verifyKey: Verify key
        :return: colChk: Collateral check

        :Example:

        .. todo: Example
        """
        # This creates the self.marketOutcomes array
        self.updateOutcomeCombinations()

        # Check if market exists
        marketIds = pd.read_sql('select distinct "marketId" from "marketBounds"', self.conn)["marketId"]
        marketChk = np.any(mInd_ == marketIds)

        # Check signature is right
        previousSigChk = previousSig == bytes(self.getPreviousOrder()['signature'][0])
        # Check signature for trade (Created in client)
        sigMsg =\
            str(p_).encode("utf-8")+\
            str(q_).encode("utf-8")+\
            str(mInd_).encode('utf-8')+\
            str(tInd_).encode("utf-8")+\
            previousSig + b'end'

        sigChk = self.checkSignature(signature, sigMsg,  verifyKey)
        # Convert sigChk to logical
        if isinstance(sigChk, bytes):
            sigChk = True

        colChk = False
        if marketChk & sigChk & previousSigChk:
            colChk = self.checkCollateral(p_, q_, mInd_, tInd_)
            if colChk:
                newTrade = pd.DataFrame({ 'price': [p_],
                                          'quantity': [q_],
                                          'marketId': [mInd_],
                                          'traderId': [tInd_],
                                          'signature': signature,
                                          'iMatched': [False],
                                          'iRemoved': [False]})
                # Append new trade
                newTrade.to_sql(name='orderBook', con=self.conn, if_exists='append', index=False)
                # Check for matches
                data = pd.read_sql_query(
                    'SELECT "tradeId" FROM "orderBook" WHERE "price" = %s AND "quantity" = %s AND "iMatched" = FALSE AND "iRemoved" = FALSE' % (p_, -q_), self.conn)               # Find a match
                # Update
                if not data.empty:
                    # Update iMatched for matching trades
                    self.conn.execute(
                        'UPDATE "orderBook" SET "iMatched"= TRUE where "tradeId" IN (%s, (SELECT MAX("tradeId") FROM "orderBook"))' % (data['tradeId'][0]))

            # Clean up trades causing collateral to fail
            allClear = False
            while not allClear:
                colChk = self.checkCollateral(tInd_ = tInd_)
                if colChk:
                    allClear = True
                else:
                    self.killMarginalOpenTrade(tInd_)

            return colChk

    # Collateral check

    def checkCollateral(self, p_=[], q_=[], mInd_ = [], tInd_=None):
        # Check collateral for new trade.
        #
        # p_, q_, mInd_, tInd_ - New trade
        # p, q, mInd, tInd - Existing trades
        # M - Market state payoffs
        # iMatched - Indicator for matched trades

        # Get p, q, mInd, tInd for trader
        data = pd.read_sql_query('SELECT "price", "quantity", "marketId", "traderId", "iMatched" FROM "orderBook" WHERE "traderId" = \'%s\' AND "iRemoved" = FALSE' % (tInd_),
                                               self.conn)
        self.p = data['price']
        self.q = data['quantity']
        self.mInd = data['marketId']  # (sort out unique marketId)
        self.tInd = data['traderId']
        self.iMatched = data['iMatched']
        # Test by appending test trade
        p = np.array(np.append(self.p, p_))
        q = np.array(np.append(self.q, q_))
        # If price is given, append.
        if p_:
            mInd = np.append(self.mInd, mInd_)
            tInd = np.append(self.tInd, tInd_)
            iMatched = np.append(self.iMatched, False)
        else:
            mInd = self.mInd
            tInd = self.tInd
            iMatched = self.iMatched

        M = self.marketOutcomes
        C, N = M.shape
        D = tInd.max()
        # Derived
        iUnmatched = np.logical_not(iMatched)
        T = len(p)  # Number of trades
        QD = np.tile(q, (D,1)).T   # Tiled quantity (traders)
        QC = np.tile(q, (C, 1)) # Tiled quantity (states)
        IM = self.ind2vec(mInd - 1,N).T# Indicator for market
        IQ = self.ind2vec(tInd-1,D) # Indicator for trader
        QDstar = QD*IQ # Tiled quantity distribured across traders
        Pstar = np.tile(p, (C, 1)) # Tiled price distributed across states
        Mstar = np.dot(M, IM) # Market outcomes across states and trades

        # Collateral calculation
        NC = np.dot((Mstar - Pstar), QDstar)
        NCstar = (Mstar-Pstar)*QC

        # Split out matched and unmatched
        matchedInd = np.where(iMatched)[0]
        unmatchedInd = np.where(iUnmatched)[0]
        NCstar_matched = NCstar[:,matchedInd]
        NCstar_unmatched = NCstar[:, unmatchedInd]

        #TC = np.sum(NCstar_matched, axis=1) + np.min(NCstar_unmatched, axis=1)


        # Total collateral calculation
        if NCstar_matched.shape[1] == 0 and NCstar_unmatched.shape[1] ==0:
            TC = NCstar_matched + NCstar_unmatched
        elif NCstar_matched.shape[1] == 0 and NCstar_unmatched.shape[1] > 0:
            TC = np.min(NCstar_unmatched, axis=1)
        elif NCstar_matched.shape[1] > 0 and NCstar_unmatched.shape[1]  == 0:
            TC = np.sum(NCstar_matched, axis=1)
        else:
            TC = np.sum(NCstar_matched, axis=1) + np.min(NCstar_unmatched, axis=1)


        colChk = np.all(TC + self.COLLATERAL_LIMIT >= 0)

        '''
        The collateral condition can be calculated simultaneously across all traders in one step by
        taking each column D columns of the second term as the minimum unmatched collateral for all 
        trades for each trader. 
        '''

        return colChk


    # Function group:
    # updateOutcomeCombinations
    # updateBoudns

    def updateOutcomeCombinations(self):
        """Update outcome combinations taking into account mins/maxes on
        branches.

        :param: None
        :return: self.outputCombinations:  (sql table) possible market states
        :return: self.marketOutcomes: (numpy nd array) Matrix of market outcome in each state
        :return: self.marketBounds: (sql table) Upper and lower bounds for all markets

        Example::
        ms = MarketServer()
        ... set up trade users/markets
        ms = ms.updateOutcomeCombinations

        """

        mT = pd.read_sql_table('marketTable', self.conn)
        # Root markets have marketBranchId ==1
        rootMarkets = mT.loc[mT['marketBranchId'] == 1, :].reset_index(drop=True)
        # Construct outcome combinations in root markets
        oC = self.constructOutcomeCombinations(rootMarkets)
        oC = oC.reset_index(drop=True)
        oC.to_sql('outcomeCombinations', self.conn, if_exists='replace', index=False)
        # Construct market bounds in all markets
        mB = self.constructMarketBounds(mT)
        marketFields = ['marketId','marketRootId', 'marketBranchId', 'marketMin', 'marketMax']
        mB = mB.loc[:, marketFields].reset_index(drop=True)
        # Full replace of market bounds
        mB.to_sql('marketBounds', self.conn, if_exists='replace', index=False)

        numMarkets = len(mB)
        numStates = oC.loc[:, 'outcomeId'].max() + 1
        # Preallocate market outcomes
        M = np.zeros((numStates, numMarkets))

        for iOutcome in range(numStates):
            # Get outcome for root market
            outcomeRow = oC.loc[oC['outcomeId'] == iOutcome, :]
            # Add outcome to market table
            # todo: more elegant way to do this
            allOutcome = mT.loc[:, marketFields].append(outcomeRow[marketFields], ignore_index=True)
            # Construct new bounds given outcome
            settleOutcome = self.constructMarketBounds(allOutcome)
            # Markets settle at marketMin=marketMax so choose either
            M[iOutcome,] = settleOutcome.loc[:, 'marketMin'].values
        # marketOutcomes is a (numStates * numMarkets) matrix of extreme market
        # states.
        self.marketOutcomes = M

    def updateBounds(self, L: float, U: float, l: float, u: float) -> object:
        """Update bounds from lower branches

        :param: L: (ndarray) lower bound for current market
        :param: U: (ndarray) upper bound for current market
        :param: l: (float64) lower bound for lower branches
        :param: u: (float64) upper bound for lower branches

        :return: L_new: (float64) new lower bound
        :return: U_new: (float64) new upper bound


        .. note::

        """

        L_new = np.min([np.max([L, l]), U])
        U_new = np.max([np.min([U, u]), L])

        return L_new, U_new

    # Function group:
    # constructOutcomeCombinations
    # constructMarketBounds
    # constructCartesianProduct
    # constructUnitVector

    def constructOutcomeCombinations(self, marketTable: object) -> object:
        """Construct all possible outcome combinations for some table of markets.

        :param: marketTable: (DataFrame) marketTable with same columns as the SQL table
        :return: marketOutcomes: (DataFrame) [marketRootId, marketBranchId,
                                              marketMin, marketMax, outcomeId]


        .. note:: Market outcome ids created new when a new market is added.

        """
        marketExtrema = self.constructMarketBounds(marketTable)
        marketExtrema = \
            marketExtrema.loc[:, ['marketRootId', 'marketMin', 'marketMax']].drop_duplicates().reset_index(drop=True)

        # TODO: This should pull out the rows into an array (something less ugly)
        exOutcome = np.zeros((len(marketExtrema), 2))
        for iRow, mRow in marketExtrema.iterrows():
            exOutcome[iRow] = [mRow['marketMin'], mRow['marketMax']]

        # Construct all combinations of output
        marketCombinations = self.constructCartesianProduct(exOutcome)
        numCombinations = len(marketCombinations)
        numMarkets = len(marketCombinations[0])

        # Get unique markets
        mT = marketTable.loc[:, ['marketId','marketRootId', 'marketBranchId']].drop_duplicates().reset_index(drop=True)

        marketIds = mT.loc[:, 'marketRootId']
        mT.loc[:, 'marketMin'] = np.nan
        mT.loc[:, 'marketMax'] = np.nan

        marketOutcomes = pd.DataFrame()
        for iOutcome in range(numCombinations):
            for iMarket in range(numMarkets):
                mT.loc[mT['marketRootId'] == marketIds.loc[iMarket], ['marketMin']] = marketCombinations[iOutcome][iMarket]
                mT.loc[mT['marketRootId'] == marketIds.loc[iMarket], ['marketMax']] = marketCombinations[iOutcome][iMarket]
                mT['outcomeId'] = iOutcome

            marketOutcomes = pd.concat([marketOutcomes, mT], ignore_index=True)

        return marketOutcomes.reset_index(drop=True).drop_duplicates()

    def constructMarketBounds(self, marketTable):
        """Construct upper and lower bounds for all markets, taking into
        account the bounds of lower branchess.

        :param: marketTable: (DataFrame) marketTable with same columns as the SQL table
        :return: marketBounds: (DataFrame) with [marketRootId, marketBranchId, marketMin, marketMax]


        .. note::

        """

        # Pull market table
        mT = pd.read_sql_table('marketTable', self.conn)

        mT = mT.loc[:, ['marketId','marketRootId', 'marketBranchId']].drop_duplicates().reset_index(drop=True)
        mT['marketMin'] = np.nan
        mT['marketMax'] = np.nan

        for iMarket, marketRow in mT.iterrows():
            mRId = marketRow['marketRootId']
            mBId = marketRow['marketBranchId']
            # Get markets with the same root on equal or lower branch
            mTmp = marketTable.loc[(marketTable['marketRootId'] == mRId) & \
                                   (marketTable['marketBranchId'] <= mBId), :].reset_index(drop=True)

            L_ = np.zeros((len(mTmp), 1))
            U_ = np.zeros((len(mTmp), 1))
            for jMarket, mRow in mTmp.iterrows():
                L_tmp = mRow['marketMin']
                U_tmp = mRow['marketMax']
                if jMarket == 0:
                    L_[jMarket] = L_tmp
                    U_[jMarket] = U_tmp
                else:
                    # Update upper and lower bounds using lower branches
                    L_new, U_new = self.updateBounds(L_[jMarket - 1], U_[jMarket - 1], L_tmp, U_tmp)
                    L_[jMarket] = L_new
                    U_[jMarket] = U_new

            # Take last element of each
            mT.loc[iMarket, 'marketMin'] = L_[-1][0]
            mT.loc[iMarket, 'marketMax'] = U_[-1][0]

        # Take what we need back
        marketBounds = mT.loc[:, ['marketId', 'marketRootId', 'marketBranchId',
                                  'marketMin', 'marketMax']]

        return marketBounds.reset_index(drop=True)

    def constructCartesianProduct(self, input):
        """Construct all possible combinations of a set

        :param: input: (ndarray) input set

        :return: cp: (list) combinations
        """
        cp = list(itertools.product(*input))
        return cp

    def constructUnitVector(self, L, x):
        """Make a vector of length L with a one in the x'th position

        :param: L: (int64) Length of unit vector
        :param: x: (int64) position of 1

        :return: u: (ndarray) unit vector

        """
        u = np.eye(int(L))[int(x)]
        return u

    # Function group:
    # getPreviousOrder


    def checkSignature(self, signature,sigMsg, verifyKey):
        # Check signature message
        return  self.verifyMessage(signature=signature, signatureMsg=sigMsg, verifyKey_hex= verifyKey)


    def getPreviousOrder(self):
        # Get previous order. If there are no orders return a dummy order
        data = pd.read_sql_query(
            'SELECT "tradeId", "signature" FROM "orderBook" WHERE "tradeId" = (SELECT max("tradeId") FROM "orderBook")',self.conn)  # Find a match
        if not data.empty:
            return data
        else:
            return pd.DataFrame({'tradeId': [0], 'signature': ['sig'.encode('utf-8')]})


    def killMarginalOpenTrade(self, tInd_):
        # Find earliest unmatched trade
        data = pd.read_sql_query(
            'SELECT min("tradeId") FROM "orderBook" WHERE "traderId" = %s and "iMatched" = FALSE AND "iRemoved" = FALSE' % (tInd_), self.conn)  # Find a match
        # Kill earliest unmatched trade
        self.conn.execute('UPDATE "orderBook" SET "iRemoved"= TRUE where "tradeId" = %s' % (data['min'][0]))

    def getPreviousMarket(self):
        """Get most recent market signature.

        Example::
             bs = BlocServer()
             bc = BlocClient()
             prevTrade = bs.getPreviousMarket()


        .. note:: Returns last trade the table or dummy market with
             signature = 's'
        .. :todo:: Better query to get most recent market


        :param None

        :return: previousMarket: (DataFrame) row of previous valid market
        """

        data = pd.read_sql_query(
            'SELECT * FROM "marketTable" order by "marketId" DESC limit 1',self.conn)  # Find a match
        if not data.empty:
            return data
        else:
            return pd.DataFrame({'tradeId': [0], 'signature': ['sig'.encode('utf-8')]})

    # Function group:
    # getVerifyKey
    # signMessage
    # verifyMessage
    # verifyTradeSignature
    # verifyMarketSignature
    # verifySignature

    def getVerifyKey(self, traderId):

        """Get verify key for trader

        :param: traderId: (int64) traderId

        :return: verifyKey: (str) verify key for traderId

        """
        queryStr = 'SELECT "verifyKey" FROM "userTable" WHERE "traderId" = \'%s\'' % (traderId)
        verifyKey = pd.read_sql(queryStr, self.conn).verifyKey[0]
        return verifyKey

    def signMessage(self, msg: object, signingKey_hex: object) -> object:
        """Sign a message

        :param: msg: message to sign
        :param: signingKey_hex: signing key as hex

        :return: signed: signed message

        """

        # Convert hex key to bytes
        signingKey_bytes = b'%s' % str.encode(signingKey_hex)
        # Generate signing key
        signingKey = nacl.signing.SigningKey(signingKey_bytes,
                                             encoder=nacl.encoding.HexEncoder)
        # Sign message
        signed = signingKey.sign(msg)
        return signed

    def verifyMessage(self, signature: bytes, signatureMsg: bytes, verifyKey_hex: str) -> object:
        """Verify a signature

        :param: signature: (bytes) signature to check
        :param: signatureMsg: (bytes) message that signature is from
        :param: verifyKey_hex: (str) verification key as string

        :return: verified: (bytes) returns signatureMsg if verified

        """

        verifyKey = nacl.signing.VerifyKey(verifyKey_hex, encoder=nacl.encoding.HexEncoder)
        verified = verifyKey.verify(signatureMsg, signature=signature)
        return verified


    def verifySignature(self, traderId, signature, signatureMsg):
        """Vefify a signature message by looking up the verify key and checking

        :param: traderId: (int64) trader id
        :param: signature: (bytes) signature
        :param: signatureMsg: (bytes) signature message

        :return: sigChk: returns if verified

        """

        verifyKey_hex = self.getVerifyKey(traderId=traderId)
        # Verify the message against the signature and verify key
        sigChk = self.verifyMessage(signature=signature, signatureMsg=signatureMsg, verifyKey_hex=verifyKey_hex)
        return sigChk

    def ind2vec(self, ind, N=None):
        ind = np.asarray(ind)
        if N is None:
            N = ind.max() + 1
        return (np.arange(N) == ind[:, None]).astype(int)


"""
b = BlocServer()

b.createUser('vk1')
b.createUser('vk2')

b.createMarket(marketRootId=1, marketBranchId=1, marketMin=0, marketMax= 1, traderId=1, previousSig=b'sig', signature=b'sig', verifyKey='vk1' )
b.createMarket(2, 1, 0.0, 1, 2, b'sig',b'sig', 'vk2' )



b.createTrade(p_=0.5, q_=1, mInd_=1, tInd_=1, previousSig=b'sig', signature=b'sig', verifyKey='vk1')
b.createTrade(0.4, 2, 2, 1,b'sig', b'sig', 'vk1')
b.createTrade(0.9,-1, 1, 2,b'sig', b'sig', 'vk2')


# createMarket(self, marketRootId, marketBranchId, marketMin, marketMax, traderId, signature, verifyKey)

for i in range(5):
    b.createTrade(0.5, 1, 1, 2, b'sig', b'sig', 'vk2')
    b.createTrade(0.5, 1, 1, 1, b'sig',b'sig', 'vk1')
    b.createTrade(0.5, -1, 1, 2,b'sig', b'sig', 'vk2')


a=1
# TODO
# add signatures for trades
# add mechanism to add markets DONE
# new database table orderBook DONE
# web api
# tests


"""