import sys
import os
import cgi



import xml.etree.ElementTree as ET
def getRootElem(modXML):
        tree = ET.parse(os.path.dirname(os.path.abspath("__file__")) +"\\Modules\\" + modXML+".xml");
        root = tree.getroot();
        return root;


def GetToolsByModule(ModuleName):
     ModRoot = getRootElem(ModuleName);
     return ModRoot.find('Tools');  

def GetOptionsByModule(ModuleName):      
    ModRoot = getRootElem(ModuleName);
    return ModRoot.find('Options');

from os.path import basename 
def printResults(dest):
    print("\n\n\n--------Results--------\n");
    for file in os.listdir(os.path.abspath(dest)):
        if os.path.isfile(os.path.abspath(dest) + "\\" + file) :
            base=os.path.basename(dest +"\\" +file);
            print("Server: " + os.path.splitext(base)[0] + "\n\n-----------------------");
            f = open(dest +"\\" +file,'r');
            print(f.read());
            #print("--------------------");
        
                            
def RunAllModules(source,dest,isFile):
        port = getPort();    
        for module in os.listdir(os.path.dirname(os.path.abspath("__file__"))+"\\Modules"):
                #print("Running module: "+module.split('.')[0]+" .......");
                DefaultOption =  GetDefaultforModule(module.split('.')[0]);
                RunToolsFromUserOption(DefaultOption, module.split('.')[0],source,dest,isFile,port);
                printResults(dest); 
     

def GetDefaultforModule(ModXML):
    return getRootElem(ModXML).find('default').text;

def RunToolsFromUserOption(UserOption,ModuleName,source,dest,isFile,port):
     Options = GetOptionsByModule(ModuleName);
     Tools = GetToolsByModule(ModuleName);
     for tempOption in Options.iter('Option'):
        if(tempOption.get('name')==UserOption):
             for command in tempOption.iter('Command'):
                 for tool in Tools.iter('Tool'):
                     if(tool.get('name')==command.find('ToolName').text):
                         for toolCommand in tool.find('Commands').iter('Command'):
                             if(command.find('ToolCommand').text == toolCommand.get('name')):
                                #print (toolCommand.get('name'));
                                
                                modCmdExec(toolCommand.find('Arg').text,source,dest,tool.find('cmd').text,tool.find('Path').text,ModuleName,tool.get('name'),isFile,port);
                                
        else:
            print("Option not found for module");
        #Use for getting the options for all modules and printing them
def PrintOptions():
    for module in os.listdir(os.path.dirname(os.path.abspath("__file__"))+"\\Modules"):
        ModRoot = getRootElem(module.split('.')[0]);
        print("List of Modules and Options\n---------------------------");
        print("Module Name: " + module.split('.')[0]);
        for option in ModRoot.find("Options").iter('Option'):
                print("Option Name: "+option.get('name'));
                print("Details: "+ option.find('Exp').text +"\n");
                
            
def FindFilterExists(output,filters): 
    for filter in filters:
        #print("Testing for: " +filter.get('name'));
        test = str(filter.text);
        if(not (test in str(output))):
            #one of the filter expressions was not found
            return False;
    return True;

import re

def RegFilter(output,filter):
    output = str(output);
    result ="";
    #Cleanup unwanted \n
    output = replaceOutputFormat(replaceOutpuOS(output));
    #print(output);
    oldoutput = output;
    for patternNode in filter.find('FilterExpressions').find('Expression').find('RegEx').iter('Pattern'):
        output=oldoutput;
        pattern = patternNode.text;
        findall = re.findall(pattern,output);
        for j in range(0,len(findall)):
            if(not re.search(re.compile(pattern),output)==None):
                    #print(filter.find('FilterOutput').text);
                    resultEdit = filter.find('FilterOutput').text;
                    resultEdit = replaceOutputFormatSpe(resultEdit); 
                    #print(re.search(re.compile(pattern),output).group(i));

                    temp = str(findall[j]);

                    if(not resultEdit.replace("{"+str(0)+ "}",temp) +"\n" in result):
                        result += resultEdit.replace("{"+str(0)+ "}",temp);
                        result+="\n"    
            #cut the string from the current postion to the end of the regular expression
            try:
                if(not re.search(re.compile(pattern),output)==None):
                    value = re.search(re.compile(pattern),output).group(0);
                    output = output[output.find(value,len(value))+len(value):]; 
            except ValueError:
                pass;
                
                
    return result;
        
def ApplyFilters(XMLMod,strOutput,strToolName):
    output = "";
    xmlToolinfo = None;
    for tool in getRootElem(XMLMod).find('Tools').iter('Tool'):
        if(tool.get('name') == strToolName):
            xmlToolinfo = tool;
            break;
    if(xmlToolinfo == None):
        return "None";
    if(xmlToolinfo.find('Filters') == None):
        return "None";
    #print("The tool " + strToolName + " has filters, applying filters...");
    #Go through all filters, find the filter that corresponds to the filtername and apply it
    for Toolfilter in tool.find('Filters').iter('FilterName'):
        for filter in getRootElem(XMLMod).find('Filters').iter('Filter'):
            if(filter.get('name') == Toolfilter.text):
                print("Testing for: "+Toolfilter.text);
                #Filter now holds the filters for the current output
                for exp in filter.find('FilterExpressions').iter('Expression'):
                    if(exp.find('ToolName').text == tool.get('name')):
                        if(not exp.find('RegEx')==None):
                            result = RegFilter(strOutput,filter);
                            if(not result==None):
                                output += result;
                                output+="\n";
                        elif(FindFilterExists(strOutput,exp.iter('InOutput'))==True):
                            output += filter.find('FilterOutput').text;
                            output+="\n";
    return output;                           
        
import shutil;   
def DeleteDestFolder(dest):
    if os.path.exists(dest):
        shutil.rmtree(dest,True);

banner = "\n                       SSL Scanner\n\n       Read more at: https://appsec-labs.com/tools\n       Author:  Gilad Ofir  -\n                Information \\ Application Security Consultant "
usage='usage: AppSecSSLScan.exe hostname [-f hostfile] [-p port] [-o outputdir]\nAppSecSSLScan.exe -h for help'

def getPort():
        for i in range(0,len(sys.argv)-1):
                if(sys.argv[i] == "-p"):
                        if(len(sys.argv)<=i):
                                print("-p was used but no port was specified!");
                                sys.exit();
                        else:
                                return num(sys.argv[i+1]);
                                print(port);
        return 443;
def num(s):
    try:
        return int(s)
    except ValueError:
        print("-p was used but no port is not a number!");
        sys.exit();
                               

def main():
        print("\n\n=============================================================\n");
        print("  __   ____  ____  ____  ____  ___    __     __   ____  ____"); 
        print(" / _\ (  _ \(  _ \/ ___)(  __)/ __)  (  )   / _\ (  _ \/ ___)");
        print("/    \ ) __/ ) __/\___ \ ) _)( (__   / (_/\/    \ ) _ (\___ \\");
        print("\_/\_/(__)  (__)  (____/(____)\___)  \____/\_/\_/(____/(____/");
        print(banner);
        print("\n\n=============================================================\n\n");
        print("Running...");
        if(checkForHostFile()):
            isFile = True;
            print("Using hostname file: "+getHostFile());
            source = getHostFile();
        else:
            if(len(sys.argv)>1):
                source = sys.argv[1];
                isFile = False;
            else:
                print(usage);
                return;
        if len(sys.argv)==2 and sys.argv[1] == "-list":
            PrintOptions();
        elif len(sys.argv)==2 and sys.argv[1]=="-h":
            print (usage);
        elif(checkForOutputdir()):
            DeleteDestFolder(sys.argv[2]);
            RunAllModules(source,getOutputdir(),isFile);
        elif not checkForOutputdir():
            DeleteDestFolder("c:\\SSLScannertemp");
            RunAllModules(source,"c:\\SSLScannertemp",isFile);
            DeleteDestFolder("c:\\SSLScannertemp");
        else:
            print (usage);
            
        print("---------------------------------------\nDone running AppSec Lab SSL Scanner....");
        input("Press Enter to continue...");
def checkForHostFile():
    for argument in sys.argv :
        if(argument == "-f"):
            return True;
    return False;  
def getHostFile():
    ind=1;
    for argument in sys.argv :
        if(argument == "-f"):
            if len(sys.argv)>ind:
                return sys.argv[ind];
            else:
                print("-f option was used but host file was not specified.\nQuitting...");
                sys.exit(); 
        ind = ind +1;
def getOutputdir():
    ind=1;
    for argument in sys.argv :
        if(argument == "-o"):
            if len(sys.argv)>ind:
                return sys.argv[ind];
            else:
                print("-o option was used but output dir was not specified.\nQuitting...");
                sys.exit(); 
        ind = ind +1;
        
def checkForOutputdir():
    for argument in sys.argv :
        if(argument == "-o"):
            return True;
    return False;     
def printModules():
        Modules = os.listdir(os.path.dirname(os.path.abspath("__file__"))+"\\Modules");
        print("List of Modules:");
        for module in Modules:
                print (module.split('.')[0]);
Modules = [];
strModules =[];
modCmdTuples={};
modCmdPrint=[];



def runproc(hostname,cmdoption,dest,modExe,modName,xmlModeName,strToolName,port): 
    #print("Hostname/IP: "+hostname);
    output = runModule(hostname,modExe,cmdoption ,os.path.dirname(os.path.abspath("__file__")) +"\\Execs\\"+modName,port);
    FilteredOutput(ApplyFilters(xmlModeName, output, strToolName),dest,hostname);
    outPuttoFile(output,dest+"\\"+strToolName+"\\"+hostname+".txt");
def modCmdExec(cmdoption,source,dest,modExe,modName,xmlModeName,strToolName,isFile,port):
        try: 
                DirHandle(dest);
                DirHandle(dest+"\\"+strToolName);
                if(not isFile):
                    #Then Source is the hostname;
                    runproc(source,cmdoption,dest,modExe,modName,xmlModeName,strToolName,port);
                hostnames = open(source);
                with open(source, 'r') as f:
                    hostnames = f.readlines();
                    for hostname in hostnames:
                        hostname = hostname.replace("\n","");
                        
                        runproc(hostname,cmdoption,dest,modExe,modName,xmlModeName,strToolName,port);
        except IOError as e:
            error = "";
                #print ("AppSec SSL Scanner error:");
                #print ("I/O error({0}): {1}".format(e.errno, e.strerror));                               

def DirHandle(outputDir):
        if not os.path.exists(outputDir):
                os.makedirs(outputDir);
import shlex
from subprocess import Popen, PIPE
def runModule(hostname,strCmd,strArgs,cmdDir,port):
        cmdDir = cmdDir.strip()
        strArgs = strArgs.replace("PyHST",hostname,1);
        #print(strArgs);
        strArgs = strArgs.replace("PyPort",str(port),1);
        #print(strArgs);
        strFullCmd = "\"" + cmdDir+"\\"+ strCmd+"\"" +" "+  strArgs;
        #print(strFullCmd);
        args = shlex.split(strFullCmd)
        #print("Running Command.......");
        proc = Popen(args, stdout=PIPE, stderr=PIPE);
        output, err = proc.communicate()
        return output;
    
def FilteredOutput(FilteredOutput,dest,hostname):
    DirHandle(dest);
    outPutAppendtoFile(FilteredOutput, dest+"\\"+hostname+".txt");
   

def outPutAppendtoFile(output,file):
    if(output=="None"):
        return;
    if(os.path.exists(file)):
        f = open(file,'r');
        if(str(output) in f.read() == True):
            f.close();
            return;
        f.close();
    if not os.path.exists(file):
        f = open(file,'w');
    else:
        f = open(file,'a');
    f.write(str(output));
    f.close(); 
def outPuttoFile(output,file):
    #print(file);
    f = open(file,'w');
    f.write(replaceOutputFormat(str(output)));
    f.close();

def replaceOutputFormatSpe(output):
     output = output.replace("\n","");
     return output;

def replaceOutputFormat(output):
    output = output.replace("\\n","\n");
    output = output.replace("\\r","");
    return output;
def replaceOutpuOS(output):
    output = output.replace("\n",os.linesep);
    output = output.replace("\\r","");
    return output;
        
main()


