# Standalone Script (K6 script) Execution in Azure


**Pre-requisites:**

1. Install Azure CLI (Refer https://adamtheautomator.com/install-azure-cli/)
2. Install NPM (Refer https://nodejs.org/en/download/package-manager/)
3. Valid Azure Subscription with Service Principle created
4. Update the .env file with environmental variable values. Refer .env.sample file

**Steps to execute the test**
1. Create the folder in your laptop.
2. Run the command "npm init -y". This will create package.json file in your folder.
3. Run the command "npm install https://github.com/volvo-cars/k6-volvo.git. This will install all the dependancies for test execution.
4. Edit the package.json under script section <br>
  "scripts": { <br>
    "test": "echo \"Error: no test specified\" && exit 1", <br>
    **"setup":"folder",** <br>
    **"startTest":"k6test"** <br>
  }<br>
5. Run the command "npm run setup". This will create the folder structure.
6. Copy your test script to "src" folder and test data file to "data" folder.
7. Run the command <br> "npm run startTest -- [your test script including extension] [Number of Virtual Users] [Duration in seconds] [SLA limit in milliseconds]". <br>
  For example, Engineer wants to run "perf.js" script with 150 users for 1 hour and expecting the response time 600 milliseconds. Then the command is <br> "npm run startTest -- perf.js 150 3600 600

For reference, please visit 
https://www.notion.so/volvocars/Azure-Standalone-Script-Execution-3a46679234e34406b84bf11ab65b77ed
