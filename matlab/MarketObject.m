classdef MarketObject < handle
    % Version of market object  that only allows q=1 or q=-1
    
    % tradeBranchId:
    %
    %           1 = Primary - default (trade initially in order book)
    %           2 = Offset (offset a primary trade => signature from primary)
    %           3 = Match (matched version of primary trade => signature from offset)
    
    % Market object with simplified tables and mock signatures.
    
    properties (SetAccess=private)
        % Table with users and public key for signatures
        userTable = table([], {}, 'VariableNames', {'traderId',...
            'verifyKey'});
        % Order book for all trades, including including order book,
        % matched, and linked trades (offsets, partials, etc)
        orderBook = table([], [], [], [], [], [], [], {}, {}, {},...
            'VariableNames',...
            {'tradeRootId', 'tradeBranchId', 'price',...
            'quantity', 'marketRootId', 'marketBranchId', 'traderId',...
            'previousSig', 'signatureMsg', 'signature'});
        % Cache order book (trades can be promoted to the order book)
        cacheBook = table([], [], [], [], [], [], [], {}, {}, {},...
            'VariableNames',...
            {'tradeRootId', 'tradeBranchId','price',...
            'quantity', 'marketRootId', 'marketBranchId', 'traderId',...
            'previousSig', 'signatureMsg', 'signature'});
        % Market table with minimum and maximum of each market.
        marketTable = table([], [], [], [], [], {}, {}, {}, 'VariableNames',...
            {'marketRootId', 'marketBranchId', 'marketMin', 'marketMax',...
            'traderId', 'previousSig', 'signatureMsg', 'signature'});
        % TODO: apply collateral only for trader 0, everyone else  gets
        % from trades.
        COLLATERAL_LIMIT = -2;
        
    end % Properties
    
    methods (Access = public) % Construct and create users/market/trade
        
        % MarketObject (constructor)
        
        % Create functions:
        % createUser
        % createMarket
        % createTrade
        
        function this = MarketObject()
            % Constructor
        end  % MarketObject
        
        function this = createUser(this, inputStruct)
            % Create a new row in this.userTable
            % e.g. 
            % mo = mo.createUser(struct('verifyKey','a'));
            % mo = mo.createUser(struct('verifyKey','b'));
            newUser = struct2table(inputStruct);
            
            % Number of users in table
            maxTraderId = height(this.userTable);
            % Add new user if not already in table
            if ~ismember(newUser.verifyKey, this.userTable.verifyKey)
                traderId = maxTraderId + 1;
                newUser = table(traderId, {newUser.verifyKey}, 'VariableNames',...
                    {'traderId', 'verifyKey'});
                this.userTable = vertcat(this.userTable, newUser);
                disp(['traderId:' num2str(traderId)])
            else
                disp('Verify key already exists');
            end
        end % createUser
        
        function this = createMarket(this, newMarket)
            % Create a new row in this.marketTable (check signature)
            % e.g. 
            %   mo.createMarket(struct('marketRootId', 1, 'marketBranchId', 1,...
            %                                'marketMin', 0, 'marketMax', 1,...
            %                                'traderId', 1, 'previousSig', 'prevSig', 'signatureMsg','sigMsg',...
            %                                'signature', 'sig'))   
            %
            
            % New market from input structure
            newMarket = struct2table(newMarket);
            
            % Check signature chain for markets
            if isempty(this.marketTable)
                % If there are no existing markets chain is ok
                chainChk = true;
            elseif newMarket.marketBranchId == 1
                % If a new root market, previous largest root market +1
                isPrevMarket  = this.marketTable.marketRootId == max(this.marketTable.marketRootId) &...
                    this.marketTable.marketBranchId == 1;
                % Pick out the previous market
                prevMarket = this.marketTable(isPrevMarket, :);
                % Check that new market root is previous market  root + 1
                % and the previous signature matches
                chainChk = newMarket.marketRootId == (prevMarket.marketRootId+1) &...
                    newMarket.marketBranchId == 1 &...
                    newMarket.prevSig == prevMarket.signature;
            elseif newMarket.marketBranchId > 1
                % If this is a branch market check that it chains to the
                % highest  existing branch on the same root market.
                isRootMarket  = this.marketTable.marketRootId == newTrade.marketRootId;
                % Pick out the previous market
                rootMarkets = this.marketTable(isRootMarket, :);
                % Pick out market with same root and largest branch id
                isMaxBranch = rootMarkets.marketBranchId == max(rootMarkets.marketBranchId);
                isPrevMarket = rootMarkets(isMaxBranch, :);
                % Pick out previous market
                prevMarket = rootMarkets(isPrevMarket, :);
                % Check that new market branch is previous market branch + 1
                % and the previous signature matches
                chainChk = newMarket.marketBranchId == (prevMarket.marketBranchId + 1) &...
                    newMarket.prevSig == prevMarket.signature;
            else
                % Any other case, chainChk is false
                chainChk = false;
            end
                           
            % Check signature of new market is valid
            sigChk = this.verifyMarketSignature(newMarket);
            % Check market range
            marketRangeChk = newMarket.marketMin <= newMarket.marketMax;
            % Checks (correct market number, signature relative to correct parent market, marketMin <= marketMax)
            if marketRangeChk & sigChk & chainChk
                checks = 1;
            else
                checks = 0;
                disp('Signature does not match, bad signature chain, or else marketMin > marketMax. Market not added.');
            end
            
            % Add market if checks pass
            if checks
                this.marketTable = vertcat(this.marketTable, newMarket);
            end
            
        end % createMarket
        
        function this = createTrade(this, pTrades, oTrades, mTrades)
            % - Check package of primary+offset+match trades exist and
            % are valid
            % - Create trade signatures 
            % - Check that sufficient collateral exists for primary trade
            % (checkCollateral)
            % - Add primary trade to this.orderBook
            % - Add all other trades to this.cacheBook
            % 
            %  Example input:
            %  primaryTrades1 = struct('traderId', {1; 1}, 'tradeRootId', {1;1}, 'tradeBranchId', {1; 1},...
            %                                            'price', {0.5;0.4}, 'quantity', {1; 1}, 'marketRootId', {1; 1},...
            %                                            'marketBranchId', {1; 1}, 'previousSig', {''; ''}, 'signatureMsg',...
            %                                            {'sigMsg1';'sigMsg2'}, 'signature', {'sigMsg1s';'sigMsg2s'});
            %  offsetTrades1 = struct('traderId', {1; 1}, 'tradeRootId', {1; 1}, 'tradeBranchId', {2; 2},...
            %                                            'price', {0.5; 0.4}, 'quantity', {-1; -1}, 'marketRootId', {1; 1},...
            %                                            'marketBranchId', {1; 1}, 'previousSig', {'sigMsg1s';'sigMsg2s'}, 'signatureMsg',...
            %                                            {'sigMsg1s';'sigMsg2s'}, 'signature', {'sigMsg1ss';'sigMsg2ss'});
            %  matchTrades1 =  struct('traderId', {1; 1}, 'tradeRootId', {1; 1}, 'tradeBranchId', {3; 3},...
            %                                            'price', {0.5; 0.4}, 'quantity', {1; 1}, 'marketRootId', {1; 1},...
            %                                            'marketBranchId', {1; 1}, 'previousSig', {'sigMsg1ss';'sigMsg2ss'}, 'signatureMsg',...
            %                                            {'sigMsg1ss';'sigMsg2ss'}, 'signature', {'sigMsg1sss';'sigMsg2sss'})                       
            % 
            %     this.createTrade(primaryTrades1, offsetTrades1, matchTrades1)
            pTrades = struct2table(pTrades);
            oTrades = struct2table(oTrades);
            mTrades = struct2table(mTrades);
            
            % Check trade package structure makes sense:
            
            % - Same trader id and trade root id
            chk1 = pTrades.traderId == oTrades.traderId  &...
                oTrades.traderId == mTrades.traderId;
            chk2 = pTrades.tradeRootId == oTrades.tradeRootId &...
                oTrades.tradeRootId == mTrades.tradeRootId ;
            % - Trade branch id 1 for primary, 2 for offset, 3 for match
            chk3 = pTrades.tradeBranchId == 1;
            chk4 = oTrades.tradeBranchId == 2;
            chk5 = mTrades.tradeBranchId == 3;                      
            % - Same price for all
            chk6 = pTrades.price == oTrades.price &...
                oTrades.price == mTrades.price;
            % - Same absolure quantity
            chk7 = abs(pTrades.quantity) == abs(oTrades.quantity) &...
                abs(oTrades.quantity) == abs(mTrades.quantity);
            % - Opposite signs for primary and offset            
            chk8 = sign(pTrades.quantity) == -1*sign(oTrades.quantity) &...
                -1*sign(oTrades.quantity) == sign(mTrades.quantity);
            % - Same market root and branch
            chk9 = pTrades.marketRootId == oTrades.marketRootId &...
                oTrades.marketRootId == mTrades.marketRootId;
            chk10 = pTrades.marketBranchId == oTrades.marketBranchId &...
                oTrades.marketBranchId == mTrades.marketBranchId;
            
            primaryOffsetMatchChk = all(chk1 & chk2 & chk3 & chk4 & chk5 &...
                chk6 & chk7 & chk8 & chk9 & chk10);            
            
            % Check quantity is -1 or 1
            validTradeQuantityChk = all(ismember(pTrades.quantity, [-1, 1]));
            
            % Check market exists
            if any( (pTrades.marketRootId(1) == this.marketTable.marketRootId) & ...
                    (pTrades.marketBranchId(1) == this.marketTable.marketBranchId))
                validMarketChk = 1;
            else
                validMarketChk = 0;
                disp('Market root and/or branch does not exist.');
            end
            
            % Check signatures of all trades match their signature msg
            for  iTrade = 1 : length(pTrades.traderId)
                sigChkPrimary(iTrade) = this.verifyTradeSignature(pTrades(iTrade,:));
                if ~isempty(this.orderBook)
                    % Find previous trade                    
                    prevTrade = this.orderBook(strcmp(this.orderBook.signature, pTrades{iTrade, 'previousSig'}), :);
                    % Find previous valid trade
                    prevValidTrade = this.getPreviousTrade;
                    % Check signature matches
                    chainChkPrimary(iTrade) = strcmp(prevTrade.signature, prevValidTrade.signature);
                else
                    % If it's the first trade it's ok
                    chainChkPrimary(iTrade) = true;
                end
                % Check signature of offset trade
                sigChkOffset(iTrade) = this.verifyTradeSignature(oTrades(iTrade,:));
                % Check previous signature of offset is signature of
                % primary
                chainChkOffset(iTrade) = strcmp(oTrades{iTrade, 'previousSig'}, pTrades{iTrade, 'signature'});
                % Check signature of match trade
                sigChkMatch(iTrade) = this.verifyTradeSignature(mTrades(iTrade, :));
                % Check prepvious signature of matched trade is signature
                % of offset
                chainChkMatch(iTrade) = strcmp(mTrades{iTrade, 'previousSig'}, oTrades{iTrade, 'signature'});
            end
            
            % All signatures  check out
            sigChk = all(sigChkPrimary & sigChkOffset & sigChkMatch);
            
            % All chains check out
            chainChk = all(chainChkPrimary & chainChkOffset & chainChkMatch);
            
            % If all checks pass, add new trade in orderBook and rest to cache.           
            if primaryOffsetMatchChk & validTradeQuantityChk & validMarketChk & sigChk & chainChk
                primaryTrades = pTrades;
                offsetTrade = oTrades;
                matchTrade = mTrades;
                % New trade is first primary trade
                newTrade = primaryTrades(1,:);
                % Alternative primary trades are other  primary trades
                altPrimaryTrades = primaryTrades(2:end, :);
                % Check collateral on first primary trade
                colChk = this.checkCollateral(newTrade);
                if colChk
                    % Add primary trade to order book
                    this.orderBook = vertcat(this.orderBook, newTrade);
                    % Add offset and match trades to cache order book
                    this.cacheBook = vertcat(this.cacheBook, altPrimaryTrades);                    
                    this.cacheBook = vertcat(this.cacheBook, offsetTrade);
                    this.cacheBook = vertcat(this.cacheBook, matchTrade);
                    % Match trades
                    this.matchTrades();
                else
                    disp(['Failed. Signature check ' num2str(sigChk) ...
                        ', valid market  check ' num2str(validMarketChk)...
                        ', valid quantity  check ' num2str(validTradeQuantityChk)...
                        ', valid input combination  check ' num2str(primaryOffsetMatchChk) ]);
                end % colChk
            end % checks
            
        end % createTrade
        
        % Public collateral check for testing: 
        
        function [colChk, netCollateral] = checkCollateral_public(this, newTrade)
            % Public check collateral method
            
            if isstruct(newTrade)
                newTrade = struct2table(newTrade);
            end
            [colChk, netCollateral] = this.checkCollateral(newTrade);
        end % checkCollateral_public
        
        function previousTrade = getPreviousTrade(this)
            % most recent signature is the highest number on the highest
            % trade number in the order book
            
            if ~isempty(this.orderBook)
                maxTrade = this.orderBook(this.orderBook.tradeRootId == max(this.orderBook.tradeRootId), :);
                previousTrade = maxTrade(maxTrade.tradeBranchId == max(maxTrade.tradeBranchId), :);
            else
                % Return root trade
                previousTrade = table(0, {'s'}, 'VariableNames', {'tradeRootId', 'signature'});
            end

            
        end % getPreviousSignature
        
    end % Public methods
    
    methods (Access = private) % Check collateral and match
                
        % Check and match functions:
        
        % checkCollateral
        % constructMarketOutcomes
        % constructPayoff
        % matchTrades
        
        function [colChk, netCollateral] = checkCollateral(this, newTrade)
            % Check if sufficient collateral exists for a newTrade by
            % constructing all output combinations for the trader. Returns
            % colChk = 0/1 (1 = suffiient collateral  exists)
            
            % Note that this should not be a public method because it could
            % be used to deduce information about the trader's positions.
            
            % Select own trades
            traderId = newTrade.traderId;
            % Get existing trades for trader
            ownTrades = this.orderBook((this.orderBook.traderId == traderId), :);
            % Get all root markets (where marketBranchId == 1)
            rootMarkets = this.marketTable(this.marketTable.marketBranchId == 1, :);
            % Get own root  markets
            ownRootMarkets = rootMarkets(ismember(rootMarkets.marketRootId,...
                [ownTrades.marketRootId(:); newTrade.marketRootId(:)]), :);
            
            % Construct corner outcome combinations in root markets (cell array of marketTables)
            outcomeCombinations = this.constructOutcomeCombinations(ownRootMarkets);
            
            for iComb = 1 : length(outcomeCombinations)
                % Add fixed outcomes to market table
                marketTable_test = outerjoin(this.marketTable,...
                    outcomeCombinations{iComb}, 'MergeKeys', true);
                % Construct payoffs for matched and unmatched trades
                matchedTrades = ownTrades(ownTrades.tradeBranchId == 3, :);
                openTrades = ownTrades(ownTrades.tradeBranchId ~= 3, :);
                
                % Payoffs for matched trades
                if ~isempty(matchedTrades)
                    matchedTradePayoffs = this.constructPayoff(matchedTrades,...
                        marketTable_test);
                else
                    matchedTradePayoffs = 0;
                end
                
                % Payoff for open (unmatched) trades
                if ~isempty(openTrades)
                    openTradePayoffs =  this.constructPayoff(openTrades,...
                        marketTable_test);
                else
                    openTradePayoffs = 0;
                end
                
                % Payoff for new trade
                newTradePayoff = this.constructPayoff(newTrade, marketTable_test);
                
                % Collateral is all matched trades + worst open trade + worst
                % outcome on new trade
                netCollateral(iComb,:) = sum(matchedTradePayoffs) + min(openTradePayoffs) + ...
                    min(newTradePayoff);
                
            end % iComb
            
            % Collateral available under all worst outcomes
            colChk = all(netCollateral>=this.COLLATERAL_LIMIT);
            
        end % checkCollateral
        
        function marketOutcomes = constructOutcomeCombinations(this, marketTable)
            % Construct all possible outcome combinations root markets
            % Output:
            % marketOutcomes is a marketTable with each possible marketMin/marketMax combination of
            % extrema for existing markets.
            
            % Get highest market minimum for each root market
            marketMaxMin = varfun(@max, marketTable, 'InputVariables',...
                'marketMin', 'GroupingVariables',...
                {'marketRootId'});
            
            % Get lowest market maximum for each root market
            marketMinMax = varfun(@min, marketTable, 'InputVariables',...
                'marketMax', 'GroupingVariables',...
                {'marketRootId'});
            
            % Extrema for each market
            marketExtrema = innerjoin(marketMaxMin, marketMinMax, 'Keys',...
                {'marketRootId'});
            % Rename extrema as marketMin and marketMax
            marketExtrema.Properties.VariableNames(...
                ismember(marketExtrema.Properties.VariableNames,...
                'min_marketMax')) = {'marketMax'};
            marketExtrema.Properties.VariableNames(...
                ismember(marketExtrema.Properties.VariableNames,...
                'max_marketMin')) = {'marketMin'};
            marketExtrema = marketExtrema(:,...
                {'marketRootId', 'marketMin',...
                'marketMax'});
            % Market min/max outcomes
            % {[market 1 min, market 1 max], [market 2 min, market 2 max], ...}
            for iMarket = 1 : height(marketExtrema)
                tmpOutcome{iMarket} = marketExtrema{iMarket, {'marketMin',...
                    'marketMax'}};
            end % iMarket
            
            % Get all combinations
            marketCombinations = this.cartesianProduct(tmpOutcome);
            numCombinations = size(marketCombinations, 1);
            numMarkets = size(marketCombinations,2);
            
            for iOutcome = 1 : numCombinations
                % Get unique markets
                mT = unique(marketTable(:, setdiff(...
                    marketTable.Properties.VariableNames,...
                    {'marketMin', 'marketMax', 'signature',...
                    'signatureMsg'})), 'rows');
                
                marketIds = mT.marketRootId;
                % Set market min/max to each outcomme combination
                for iMarket = 1 : numMarkets
                    mT{mT.marketRootId == marketIds(iMarket),...
                        {'marketMin', 'marketMax'}} = ...
                        [marketCombinations(iOutcome, iMarket),...
                        marketCombinations(iOutcome, iMarket)];
                end % jOutcome
                marketOutcomes{iOutcome} = mT;
            end % iMarket
            
        end % constructOutputCombinations
                
        function this = matchTrades(this)
            % Match trades in this.orderBook
            % - Checks if matchable trade exists
            % - Checks collateral for both sides
            % - Writes trade (adds offsetting unmatched trade and corresponding matched trade)
            
            % Iterate through markets
            for iMarket = 1 : height(this.marketTable)
                allMatched = false;
                marketTmp = this.marketTable(iMarket,:);
                while allMatched == false
                    % Get current unmatched trades for target market
                    ob = innerjoin(this.orderBook,...
                        marketTmp(:, {'marketRootId', 'marketBranchId'}));
                    % Calculate number of branches on trade 
                    numelOrderBook = varfun(@numel, ob, 'GroupingVariables',...
                        {'traderId', 'tradeRootId', 'price'},...
                        'InputVariables', {'quantity'});
                    % Only consider trades without offsets in the order
                    % book
                    ob = innerjoin(ob, numelOrderBook(numelOrderBook.GroupCount == 1, :));
                    % Remove GroupCount
                    ob = ob(:, this.orderBook.Properties.VariableNames);
                    % Separate bids and asks 
                    bids = ob(ob.quantity ==1, :);
                    asks = ob(ob.quantity ==-1, :);
                    % Get max bids/asks
                    maxBid = bids(bids.price == max(bids.price), :);
                    minAsk = asks(asks.price == min(asks.price), :);
                                        
                    if minAsk.price <= maxBid.price

                            % Add both trades to matched and offset from
                            % unmatched
                            colChkMaxBid = this.checkCollateral(maxBid);
                            colChkMinAsk = this.checkCollateral(minAsk);
                            
                            % If either of the collateral checks fail,
                            % remove a trade and try again.
                            if colChkMaxBid & colChkMinAsk
                                this = this.writeMatchedTrade(maxBid);
                                this = this.writeMatchedTrade(minAsk);
                            elseif ~colChkMaxBid & colChkMinAsk
                                this = this.removeMarginalTrade(maxBid);
                            elseif colChkMaxBid & ~colChkMinAsk
                                this = this.removeMarginalTrade(minAsk);
                            else
                                this = this.removeMarginalTrade(maxBid);
                                this = this.removeMarginalTrade(minAsk);
                            end
                                
                    else
                        % No trades to match
                        allMatched = true;
                    end % minAsk.price <= maxBid.price
                    
                end % while allMatched = false
            end % iMarket
            
        end % matchedTrades
        
    end % methods (Access = private)
    
    methods (Access = private) % Mutate trades (write/reduce marginal)
        
        % Trade mutation functions:
        % writeMatchedTrades
        % reduceMarginalTrade
        
        function this = writeMatchedTrade(this, targetTrade)
            % Add trade by finding valid offset and matched trade
            
            % Write offset to original unmatched trade (previous sig from root trade)
            % Find closest offset trade
            offsetTrade = this.findOffsetTrade(targetTrade);
            % Add offset trade  (TODO sig check in function and remove from cache)
            this.orderBook = vertcat(this.orderBook, offsetTrade);
            % Write matched (previous sig from offset trade)
            % Find closest match trade 
            matchedTrade = this.findMatchedTrade(offsetTrade);
            % Add match trade (TODO: sig check and remove from
            % cache)
            this.orderBook = vertcat(this.orderBook, matchedTrade);
        end % writeMatchedTrade
        
        function this = removeMarginalTrade(this, targetTrade)
             % Remove 
            
            % Write offset to original unmatched trade (previous sig from root trade)
            % Find closest offset trade
            offsetTrade = this.findRemoveTrade(targetTrade);
            % Add offset trade  (TODO sig check in function and remove from cache)
            this.orderBook = vertcat(this.orderBook, offsetTrade);
      
        end
        
        
    end % methods (Access = private)
    
    methods (Access = private) % Find offset/matched
        
        % Find offset trade functions:
        % findValidOffseteTrade
        % findMatchedTrade
        
        function offsetTrade = findOffsetTrade(this, targetTrade)
            % Find offset
            isOffset = strcmp(this.cacheBook.previousSig, targetTrade.signature) &...
                this.cacheBook.price == targetTrade.price & ...
                this.cacheBook.tradeRootId == targetTrade.tradeRootId & ...
                this.cacheBook.tradeBranchId == 2 & ... 
                this.cacheBook.traderId == targetTrade.traderId;
            offsetTrade = this.cacheBook(isOffset, :);
            
        end % findMatchedTrade
        
        function matchedTrade = findMatchedTrade(this, offsetTrade)
            % Return closest valid matched trade signed from offsset trade
            isMatch = strcmp(this.cacheBook.previousSig, offsetTrade.signature) &...
                            this.cacheBook.price == offsetTrade.price & ...                
                            this.cacheBook.tradeRootId == offsetTrade.tradeRootId & ...
                            this.cacheBook.tradeBranchId == 3&... 
                            this.cacheBook.traderId == offsetTrade.traderId;
                        
            matchedTrade = this.cacheBook(isMatch, :);
            
        end % findMatchedTrade
        
        function removeTrade = findRemoveTrade(this, targetTrade)
            % Find an trade from the same traderId in the orderbook with no
            % existing offset
            ob = innerjoin(this.orderBook,...
                targetTrade(:, {'marketRootId', 'traderId'}));
            % Calculate number of branches on trade 
            numelOrderBook = varfun(@numel, ob, 'GroupingVariables',...
                {'traderId', 'tradeRootId', 'price'},...
                'InputVariables', {'quantity'});
            % Only consider trades with no offset in orderbook
            ob = innerjoin(ob, numelOrderBook(numelOrderBook.GroupCount == 1, :));
            
            % Dont let a trade remove itself
            ob = ob(ob.tradeRootId ~= targetTrade.tradeRootId, :);
            
            % Kill first trade that fits the criteria. 
            removeTrade = ob(1,:);
       
            
        end % findRemoveTrade
                        
    end % private methods
    
    methods (Access = private, Static) % Utility functions
        
        % Utility functions:        
        
        function payoffs = constructPayoff(orderBook, marketTable)
            % Construct minimum payoffs for each trades given marketTable.
            % Output:
            % payoffs - vector of minimum calculated possible payoff for each trade
            
            % Get highest market minimum for each market
            marketMaxMin = varfun(@max, marketTable, 'InputVariables',...
                'marketMin', 'GroupingVariables',...
                {'marketRootId', 'marketBranchId'});
            
            % Get lowest market maximum for each market
            marketMinMax = varfun(@min, marketTable, 'InputVariables',...
                'marketMax', 'GroupingVariables',...
                {'marketRootId', 'marketBranchId'});
            
            % Cumulative minimum along each market branch (inelegant)
            for iMarket = 1 : height(marketMaxMin)
                mRId = marketMaxMin(iMarket, :).marketRootId;
                mBId = marketMaxMin(iMarket, :).marketBranchId;
                parentMarkets = marketMaxMin(marketMaxMin.marketRootId...
                    == mRId & marketMaxMin.marketBranchId <= mBId, :);
                % Higest market minium at branch
                marketMaxMin.branchMarketMin(iMarket) =...
                    max(parentMarkets.max_marketMin);
            end % iMarket
            
            % Cumulative maximum along each market branch
            for iMarket = 1 : height(marketMaxMin)
                mRId = marketMinMax(iMarket, :).marketRootId;
                mBId = marketMinMax(iMarket, :).marketBranchId;
                parentMarkets = marketMinMax(marketMinMax.marketRootId== mRId ...
                    & marketMinMax.marketBranchId <= mBId,:);
                % Lowest market maximum at branch
                marketMinMax.branchMarketMax(iMarket) =...
                    min(parentMarkets.min_marketMax);
            end % iMarket
            
            % Add maxmin and minmax to orderBook
            minMax_test = outerjoin(orderBook, marketMinMax,...
                'Type', 'left', 'MergeKeys', true);
            
            maxMin_test = outerjoin(orderBook, marketMaxMin,...
                'Type', 'left', 'MergeKeys', true);
            
            % Construct  payoff in both  casess
            minMax_payoff = (minMax_test.branchMarketMax -...
                minMax_test.price) .* minMax_test.quantity;
            maxMin_payoff = (maxMin_test.branchMarketMin -...
                maxMin_test.price) .* maxMin_test.quantity;
            
            % Worst possible payoffs for each trade in orderBook
            payoffs = min([minMax_payoff, maxMin_payoff], [], 2);
            
        end % constructPayoff
        
        % cartesianProduct - cartesianProduct product
        
        function C = cartesianProduct(input)
            % Construct cartesianProduct product of e.g. {{[1 2]}, {[2 3]}, {[4,5]}}.
            % Used to create combination of min/max market outcomes across
            % multiple markets.
            
            args = input;
            n = length(input);
            [F{1:n}] = ndgrid(args{:});
            for i=n:-1:1
                G(:,i) = F{i}(:);
            end
            C = unique(G , 'rows');
        end % cartesianProduct
        
        
    end % private methods
    
    methods (Access = public) % Signature methods (mock for matlab version)
        
        % generateSignatureKeys
        % signMessage
        % verifyMessage
        
        function [signingKey_hex, verifyKey_hex] = generateSignatureKeys(this)
            % Generate modk sig/verify pairs
            signingKey_hex = 'sk'
            verifyKey_hex = 'vk';
        end % generateSignatureKeys
        
        function signed = signMessage(this, msg, signingKey_hex)
            % Generate mock signature as message + an s
            signed = [msg, 's'];
        end %signMessage
        
        function verified = verifyMessage(this, signature, signatureMsg, verifyKey_hex)
            % For mock just check that signature is correct
            if strcmp(signatureMsg, [msg, 's'])
                verified = true;
            else
                verified = false;
            end
            
        end %verifyMessage
                    
        function verifyKey = getVerifyKey(this, traderId)
            %         # Get verify key for trader
            %         verifyKey =  pd.read_sql('SELECT verifyKey FROM userTable WHERE'
            %                                  ' traderId = "%s"' %(traderId), this.conn
            %                                  ).verifyKey[0]
            %         return verifyKey
            verifyKey = 'vk';
        end % verifyKey
        
        function signatureKey = getSignatureKey(this, traderId)
            %         # Get signature key for trader (Not in production)
            %         # TODO: Remove for production
            %         signatureKey =  pd.read_sql('SELECT signatureKey FROM userTable WHERE'
            %                                     ' traderId = "%s"' %(traderId), this.conn
            %                                     ).signatureKey[0]
            %         return signatureKey
            signatureKey = 'sk';
        end % signatureKey
                       
        %     # Chain signatures (all need to be on client side eventually)
        
        function signedMarketTable = signMarketTable(this, newMarket,  signatureKey_hex)

            %         # Encode signature message in bytes
            %         msg = b'%s%s%s%s%s%s' % (newMarket.prevSig, newMarket.traderId.encode("utf-8"), newMarket.underlying.encode("utf-8"),
            %                            str(newMarket.marketMin).encode("utf-8"), str(newMarket.marketMax).encode("utf-8"), str(newMarket.expiry).encode("utf-8"))
            %
            %         signedOpenMarketData = this.signMessage(msg=msg,
            %                                                    signingKey_hex=signatureKey_hex)
            %         return signedOpenMarketData
            signedMarketTable = 'signedMarket';
        end % signedMarketTable
        
        function signedOrderBook = signOrderBook(this, newTrade, signatureKey_hex)
            %         # Sign previous signature
            %
            %         # Encode signature message in bytes
            %         msg = b'%s%s%s%s%s' % (newTrade.prevSig, newTrade.traderId.encode("utf-8"), str(newTrade.marketId).encode("utf-8"),
            %                            str(newTrade.price).encode("utf-8"), str(newTrade.quantity).encode("utf-8"))
            %
            %         signedOrderBook = this.signMessage(msg=msg,
            %                                                    signingKey_hex=signatureKey_hex)
            %         return signedOrderBook
            signedOrderBook = 'signedTrade';
        end % signOrderBook       
        
        function verified = verifyTradeSignature(this, newTrade)
            % Verify trade signature is correct
            verified = this.verifySignature(newTrade.traderId, newTrade.signature, newTrade.signatureMsg);
        end % verifyTradeSignature        
        
        function verified = verifyMarketSignature(this, newMarket)
            % Verify market signature is correct
            verified = this.verifySignature(newMarket.traderId, newMarket.signature, newMarket.signatureMsg);
        end % verifyTradeSignature       
        
        function verified = verifySignature(this, traderId, signature, signatureMsg)
            %         # Vefify a signature messsage by looking up the verify key and checking
            %         verifyKey_hex = this.getVerifyKey(traderId=traderId)
            %         # Verify the message against the signature and verify key
            %         return this.verifyMessage(signature=signature,
            %                                   signatureMsg=signatureMsg,
            %                                   verifyKey_hex=verifyKey_hex)
            % Mock signature is message + 's'
            if iscell(signatureMsg)
                verified = strcmp(signature, [signatureMsg{1}, 's']);
            else
                verified = strcmp(signature, [signatureMsg, 's']);
            end
        end % verifySignature
                
    end % signature methods
    
end % MarketObject





