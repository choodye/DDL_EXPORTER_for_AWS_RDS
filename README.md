# DDL_EXPORTER_for_AWS_RDS for migration assessment in AWS DMS Schema Conversion (DMS SC)

This set of Powershell scripts is designed to aid Solution Architects with exporting, formatting self managed SQL Server database schemas to be imported into AWs RDS SQL Server for an assessment in AWS DMS Schema Conversion.

ddl_exporter_v2.ps1 - Exports DDLs from SQL Servers across your enterprise. Exports only schema objects but no data.
  It can use default or named instances
  You can provide server/instances interactively or from a CSV input file (servers.csv)
  It accespts Integrated Authentication or SQL Server based logins

cleanupDDL.ps1 - Formats the output from  SQL Servers with variable file locations.
  Cleans Up the drive based file locations from the create database
  Removes the CREATE ROLES entrise in each DDL, as they are not necessary for the assessment or conversion to Amazon Aurora PostgreSQL

CreateDatabases.ps1 - Executes each DDL and creates an empty database for each .SQL file that contains only schema but no data.
