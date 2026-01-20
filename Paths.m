function r = Paths()
global DIRS;
if isunix % linux development environment (ignore or delete this)
    r.data =  'test_data';
    r.xfiles = '/home/luke/Dropbox/zpep_work/xfiles/';
    r.config = 'config.mat';
else
    try % try to use SetDefaultDirs if available
        SetDefaultDirs();
        r = DIRS;
        r.config = fullfile(getenv('USERPROFILE'),'mpep_config.mat');
    catch % SetDefaultDirs not available.
        % Edit these paths to make mpep work in the lab
        % directory where mpep saves experiment logs
        r.data = 'C:\Users\bugeon\Documents\MATLAB\Data';
        % directory where mpep expects to find xfiles
        r.xfiles = '\\netdata\EqpCossart\Stephane Bugeon\Code\Data\xfiles';
        % config path for mpep
        r.config = fullfile(getenv('USERPROFILE'),'mpep_config.mat');
    end
end

