classdef DataHostCommunicator < handle
    %DatCommunicator communicates with data aquisition hosts.
    
    properties
        oneWayHosts = {} % cell array of ip addresses
        bidirectionalHosts = {} 
    end
    
    properties(GetAccess = private)
        experimentNumber;
        animal;
        series;
        stimNum = -1;
        blockCount = 0;
        
        inPort = 1103;
        outPort = 1001;
        outPortTL = 1011;
        socket;

        % 1 min timeout on bidirectional host echo
        timeout = 60*1000;
        bips;
    end
    
    methods
        function connect(self)
            import java.net.*;
            self.socket = DatagramSocket(self.inPort);
            self.bips = cell(1, length(self.bidirectionalHosts));
            for i = 1:length(self.bidirectionalHosts)
                sendString(self.socket, 'hello', self.bidirectionalHosts{i}, self.outPort);
                % will throw exception if anything does not respond
                try
                    receiveFromSocket(self.socket, 100, 2000); % short timeout for pings
                catch e
                   error(['Unable to communicate with datahost '  self.bidirectionalHosts{i}]);
                end
                % Get ip as string address from host name (could be either, this is
                % an easy way to check) Use these later to check for
                % replies
                adr = java.net.InetAddress.getByName(self.bidirectionalHosts{i});
                self.bips{i} = char(adr.getHostAddress());
            end
        end
        
        function startExperiment(self, animal, series, experimentNumber)
            self.experimentNumber = experimentNumber;
            self.animal = animal;
            
            % in this new version of mpep series comes in as a string. But
            % this all is built to use the number, so we'll just keep that.
            % 
            seriesAsNum = str2num(datestr(datenum(series, 'yyyy-mm-dd'), 'yyyymmdd'));
            self.series = seriesAsNum;
            self.blockCount = 0;
            
            str = sprintf('ExpStart %s %d %d', self.animal, self.series, self.experimentNumber);
            self.sendAll(str);
            disp(str);

        end
        
        function startBlock(self)
            self.blockCount = self.blockCount+1;            
            str = sprintf('BlockStart %s %d %d %d', self.animal, self.series, ...
                self.experimentNumber, self.blockCount);
            self.sendAll(str);
            disp(str);

        end
        
        % send a stim start with arbitrary block number
        function stimStartTest(self, animal, series, experimentNumber, n, blockNumber, duration)
            seriesAsNum = str2num(datestr(datenum(series, 'yyyy-mm-dd'), 'yyyymmdd'));
            self.stimNum = n;
            str = sprintf('StimStart %s %d %d %d %d %d', animal, seriesAsNum, ...
                experimentNumber, blockNumber, self.stimNum, duration);
            self.sendAll(str);
            disp(str);
        end
        
        function stimStart(self, n, duration)        
            self.stimNum = n;
            str = sprintf('StimStart %s %d %d %d %d %d', self.animal, self.series, ...
                self.experimentNumber, self.blockCount, self.stimNum, duration);
            self.sendAll(str);
            disp(str);
        end
        
        function stimEnd(self)
            str = sprintf('StimEnd %s %d %d %d %d', self.animal, self.series, ...
                self.experimentNumber, self.blockCount, self.stimNum);
            self.sendAll(str);
            disp(str);
        end
        
        function stimEndTest(self, animal, series, experimentNumber, n, blockNumber)
            seriesAsNum = str2num(datestr(datenum(series, 'yyyy-mm-dd'), 'yyyymmdd'));
            self.stimNum = n;
            str = sprintf('StimEnd %s %d %d %d %d', animal, seriesAsNum, ...
                experimentNumber, blockNumber, self.stimNum);
            self.sendAll(str);
            disp(str);  
        end
        
        function endBlock(self)
            str = sprintf('BlockEnd %s %d %d %d', self.animal, self.series, ...
                self.experimentNumber, self.blockCount);
            self.sendAll(str);
            disp(str);
        end 
        
        function endExperiment(self)           
            str = sprintf('ExpEnd %s %d %d', self.animal, self.series, self.experimentNumber);
            self.sendAll(str);
            disp(str);
        end
        
        function interruptExperiment(self)
            str = sprintf('ExpInterrupt %s %d %d', self.animal, self.series, self.experimentNumber);
            self.sendAll(str);
            disp(str);
        end
        
        
        % Zero repeat blocks for fill up stimulus.
        function startZeroBlock(self)
            str = sprintf('BlockStart %s %d %d %d', self.animal, self.series, ...
                self.experimentNumber, 0);
            self.sendAll(str);
            disp(str);
        end
        
        function endZeroBlock(self)
            str = sprintf('BlockEnd %s %d %d %d', self.animal, self.series, ...
                self.experimentNumber, 0);
            self.sendAll(str);
            disp(str);
        end 
        
        function sendAll(self, str)
           % send packet to one way hosts
           x = @(host)(sendString(self.socket, str,  host, self.outPort));
           cellfun(x, self.oneWayHosts);
           
           % send packet to Timeline (SB)
           x = @(host)(sendString(self.socket, str,  host, self.outPortTL));
           cellfun(x, self.oneWayHosts);
           
           % send packet to all bidirectional hosts
           x = @(host)(sendString(self.socket, str,  host, self.outPort));
           cellfun(x, self.bidirectionalHosts);
           
           % check responses from all hosts - throw error if echo not
           % received from one or wrong thing echoed back.
           n = length(self.bidirectionalHosts);
           if n == 0
               return;
           end
           
           rcvMap = containers.Map(self.bips, num2cell(zeros(1,n)));
           % recieve packets until all data hosts have echoed back
           try
               while ~isequal(cell2mat(rcvMap.values),ones(1,n))
                   try
                    [bytes, address] = receiveFromSocket(self.socket, 100, self.timeout);
                   catch e
                        doubleTimeout = 'Double the timeout and try again';
                        infTimout = 'Increase timeout to infinity and try again';
                        choice = questdlg(...
                            'There was a timeout when reciving packet from data hosts. What do you want to do?',...
                            'Timeout',...
                            'Double the timeout time and try again',...
                            'Increase timeout to infinity and try again',...
                            'Give up',...
                            'Double the timeout time and try again');
                        
                        switch choice
                            case  doubleTimeout
                                self.timeout  = self.timeout*2;
                                continue;
                            case infTimout
                                self.timeout = 0;
                                continue;
                            otherwise
                                error(e); 
                        end
                   end
                   if ~strcmp(char(bytes), str)
                       disp(['Packet from data acquisition host was different'...
                       ' from what was sent. Pretending it was echo and continuing.']);
                   end
                   if ~rcvMap.isKey(address)
                       disp(['Packet on data aquisition host port received'...
                       ' which was from an unknown address. Ignorning and continuing.']);
                       continue;
                   end
                   if rcvMap(address) == 1
                       disp(['Duplicate echo packet received from data acquisition host.'...
                       'Ignoring and continuing.']);
                   end
                   rcvMap(address) = 1; % record received
               end
           catch e
               error('Did not recieve response from data host');
           end
           
        end
        
        function disconnect(self)
            if ~isempty(self.socket)
                self.socket.close();
            end
        end
        
        function delete(self)
           self.disconnect(); 
        end
    end
    
end

