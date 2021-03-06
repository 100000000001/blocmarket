classdef testMarketObject < matlab.unittest.TestCase
    % test MarketObject_new functionality
    
    properties
        mo % market object
        mc % market client
    end % properties
 
    methods(TestMethodSetup)
        
        function createMarketObject(testCase)
            
            % Create market object
            testCase.mo = MarketObject();
            testCase.mc = MarketClient();
        end % createMarketObject
        
        function testCreateMarket(testCase)
           % Create a market on (0, 1) and a sub market (0.1, 0.9)
           
           % Create market11
            testMarket = testCase.mc.marketMaker(testCase.mo.getPreviousMarket, 1, 1, 0, 1, 1);
            testCase.mo.createMarket(testMarket);   
             
           % Create a branch of first market  
           testMarket = testCase.mc.marketMaker(testCase.mo.getPreviousMarket, 1, 2, 0.1, 0.9, 1);
           testCase.mo.createMarket(testMarket);                           
            
           % Create second root market
           testMarket = testCase.mc.marketMaker(testCase.mo.getPreviousMarket, 2, 1, 0, 1, 1);
           testCase.mo.createMarket(testMarket);    
           
           
           testCase.verifyNotEmpty(testCase.mo.marketTable)
        end % testCreateMarket
        
        function testCreateUser(testCase)
            % Create two traders
            testCase.mo = testCase.mo.createUser(struct('verifyKey','a'));
            testCase.mo = testCase.mo.createUser(struct('verifyKey','b'));
            testCase.verifyNotEmpty(testCase.mo.userTable);
        end % testCreateUser        
        
    end % TestMethodSetup
 
%     methods(TestMethodTeardown)
%         function destroyMarketObject(testCase)
%             testCase.mo = [];
%         end
%     end % TestMethodTearDown
    
    methods (Test)
        
        function testSettleMarketUp(testCase)
            % Settle root market (1,1) at 1 and ensure that
            % - Market (1,1) settles at 1
            % - Market (1,2) settles at 0.9
            settleMarket= testCase.mc.marketMaker(testCase.mo.getPreviousMarket, 1, 1, 1, 1, 1);
            testCase.mo = testCase.mo.createMarket(settleMarket);
            marketBounds = testCase.mo.marketBounds;
            expectedBounds = table([1;1], [1;2], [1;0.9], [1;0.9],...
                'VariableNames', {'marketRootId', 'marketBranchId',...
                'marketMin', 'marketMax'});
            % Import table comparer thing
            import matlab.unittest.constraints.TableComparator
            import matlab.unittest.constraints.NumericComparator
            import matlab.unittest.constraints.IsEqualTo
            testCase.verifyThat(marketBounds(1:2, :),IsEqualTo(expectedBounds, ...
                'Using',TableComparator(NumericComparator)));
        end % testSettleMarketUp
        
        function testSettleMarketDown(testCase)
            % Settle root market (1,1) at 0 and ensure that
            % - Market (1,1) settles at 0
            % - Market (1,2) settles at 0.1
            settleMarket= testCase.mc.marketMaker(testCase.mo.getPreviousMarket, 1, 1, 0, 0, 1);
            testCase.mo = testCase.mo.createMarket(settleMarket);
            marketBounds = testCase.mo.marketBounds;
            expectedBounds = table([1;1], [1;2], [0;0.1], [0;0.1],...
                'VariableNames', {'marketRootId', 'marketBranchId',...
                'marketMin', 'marketMax'});
            % Import table comparer thing
            import matlab.unittest.constraints.TableComparator
            import matlab.unittest.constraints.NumericComparator
            import matlab.unittest.constraints.IsEqualTo
            testCase.verifyThat(marketBounds(1:2,:),IsEqualTo(expectedBounds, ...
                'Using',TableComparator(NumericComparator)));
        end % testSettleMarketDown        
        
        function testMatchTrade(testCase)
            
            % Add some trades and check a match for (q=1, p=0.5/0.4).
            
            tradePackage =  testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 1, 1, 1, [0.5; 0.4], 1);          
            testCase.mo = testCase.mo.createTrade(tradePackage);
            
            % Add matching trade by for trader 2 in same market
            tradePackage =  testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 2, 1, 1, [0.5; 0.6], -1);          
       
            testCase.mo = testCase.mo.createTrade(tradePackage);            
            
            % Add an unmatched trade (@0.8/0.9)
            tradePackage =  testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 2, 1, 1, [0.8; 0.9], -1);       
            
            % Create trade                           
            testCase.mo = testCase.mo.createTrade(tradePackage);   
            
            % There should be three matched trades and one open trade
            testCase.verifyEqual(height(testCase.mo.orderBook),7);
            
            % Check collateral for a fourth trade (sign off last primary)            
            tradePackage =  testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 2, 1, 1, [0.9], -1);    
           
            [colChk, colNum]  = testCase.mo.checkCollateral(tradePackage(tradePackage.tradeBranchId==1,:));
            
            testCase.verifyTrue(all(colChk));
            testCase.verifyEqual(colNum, [-0.5 1.3; -0.5 1.3; 0.5 -0.7; 0.5 -0.7], 'AbsTol', 1e-10);                                     
            
        end % testMatchTrade
        
        function testRemoveTrade(testCase)
            
            % Put in five open trades in market  1
            % Match five  trades in market 2
            % Check that open trades are offset in market 1 as part of the
            % final match

            % Trader one puts in five orders in market 1
            for i = 1 : 5
                testCase.mo = testCase.mo.createTrade(testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 1, 1, 1, [0.4], 1))
            end
            % Five matched orders in market 2
            for i = 1 : 5
                testCase.mo = testCase.mo.createTrade(testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 1, 2, 1, [0.5], 1))
                testCase.mo = testCase.mo.createTrade(testCase.mc.tradeMaker(testCase.mo.getPreviousTrade, 2, 2, 1, [0.5], -1))    
            end % i
            
            % Run collateral checks
            [c, t, a] = testCase.mo.checkCollateral(table());
            testCase.verifyEqual(c, [true, true]);
            
        end % testRemoveTrade 
        
        
    end % tests  
    
end % classdef 