classdef MarketClient 
    % Market client
    
    properties
        signingKey_hex 
        verifyKey_hex
    end % properties
    
    methods (Access = public)
        
        function this = MarketClient()
            % Constructor
        end % marketClient
    
        function this = generateSignatureKeys(this)
            % Generate mock sig/verify pairs. (Client)
            this.signingKey_hex = 'sk';
            this.verifyKey_hex = 'vk';
        end % generateSignatureKeys
        
        function signed = signMessage(this, msg, signingKey_hex)
            % Generate mock signature as message + an s (Client)
            signed = [msg, 's'];
        end %signMessage
        
        function signatureKey = getSignatureKey(this, traderId)
            % (client)
            %         # Get signature key for trader (Not in production)
            %         # TODO: Remove for production
            %         signatureKey =  pd.read_sql('SELECT signatureKey FROM userTable WHERE'
            %                                     ' traderId = "%s"' %(traderId), this.conn
            %                                     ).signatureKey[0]
            %         return signatureKey
            signatureKey = 'sk';
        end % signatureKey
                              
        function signedMarketTable = signMarketTable(this, newMarket,  signatureKey_hex)
            % (client)
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
            % (client)
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
        
    end % public methods
    
    methods (Access = public, Static)
        
        function tradePackage = tradeMaker(prevTrade, traderId, marketRootId, marketBranchId, price, quantity)
            % Create test trade package with dummy +s signatures

            % Example:
            % tradePackage =  mc.tradeMaker(mo.getPreviousTrade, 1, 1, 1, [0.5; 0.4], 1)

            % prevTrade= mo.getPreviousTrade;
            prevSig = prevTrade.signature{1};
            tradeRootId = prevTrade.tradeRootId+1;


            traderId_ = repmat(traderId, size(price));
            tradeRootId_ = repmat(tradeRootId, size(price));
            tradeBranchId_p = repmat(1, size(price));
            tradeBranchId_o = repmat(2, size(price));
            tradeBranchId_m = repmat(3, size(price));
            price_ = price;
            quantity_ = repmat(quantity, size(price));
            negQuantity_ = repmat(-quantity, size(price));

            marketRootId_ = repmat(marketRootId, size(price));
            marketBranchId_ = repmat(marketBranchId, size(price));
            prevSig_p = repmat({prevSig}, size(price));
            prevSig_o = repmat({[prevSig  's']}, size(price));
            prevSig_m = repmat({[prevSig  'ss']}, size(price));
            sig_p = prevSig_o;
            sig_o = prevSig_m;
            sig_m = repmat({[prevSig  'sss']}, size(price));

            pT = table(traderId_, tradeRootId_, tradeBranchId_p,...
                price_, quantity_, marketRootId_, marketBranchId_,...
                prevSig_p, prevSig_p, sig_p, 'VariableNames', {'traderId',...
                'tradeRootId', 'tradeBranchId','price', 'quantity',...
                'marketRootId', 'marketBranchId', 'previousSig',...
                'signatureMsg', 'signature'});

            oT = table(traderId_, tradeRootId_, tradeBranchId_o,...
                price_, negQuantity_, marketRootId_, marketBranchId_,...
                prevSig_o, prevSig_o, sig_o, 'VariableNames', {'traderId',...
                'tradeRootId', 'tradeBranchId','price', 'quantity',...
                'marketRootId', 'marketBranchId', 'previousSig',...
                'signatureMsg', 'signature'});     
            
             mT = table(traderId_, tradeRootId_, tradeBranchId_m,...
                price_, quantity_, marketRootId_, marketBranchId_,...
                prevSig_m, prevSig_m, sig_m, 'VariableNames', {'traderId',...
                'tradeRootId', 'tradeBranchId','price', 'quantity',...
                'marketRootId', 'marketBranchId', 'previousSig',...
                'signatureMsg', 'signature'});              
            

            tradePackage = vertcat(pT, oT, mT);


        end % tradeMaker       
        
        function market = marketMaker(prevMarket, marketRootId, marketBranchId, marketMin, marketMax, traderId)
            % Create test market with dummy +s signature

            pms = prevMarket.signature;

            market =  struct('marketRootId', marketRootId, 'marketBranchId', marketBranchId,...
                                           'marketMin', marketMin, 'marketMax', marketMax,...
                                           'traderId', traderId, 'previousSig', pms,...
                                           'signatureMsg', pms,...
                                           'signature', [pms{1}, 's']);
                           
        end % marketMaker
    end % public methods
    

end % classdef