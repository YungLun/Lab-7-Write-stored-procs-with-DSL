USE AdventureWorks2019;
GO

--Task 1 ¡V Setup and Preparation
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Reporting')
EXEC('CREATE SCHEMA Reporting AUTHORIZATION dbo;')
GO

IF OBJECT_ID('Reporting.ExecutionLog', 'U') IS NOT NULL
    DROP TABLE Reporting.ExecutionLog;
GO

CREATE TABLE Reporting.ExecutionLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    ProcedureName NVARCHAR(100),
    ExecutedSQL NVARCHAR(MAX),
    ExecutionDate DATETIME DEFAULT GETDATE(),
    ErrorMessage NVARCHAR(4000)
);
GO
 


--Task 2 ¡V Create a Basic Stored Procedure
IF OBJECT_ID('Reporting.GetSalesByTerritory', 'P') IS NOT NULL
    DROP TABLE Reporting.GetSalesByTerritory;
GO

CREATE OR ALTER PROCEDURE Reporting.GetSalesByTerritory
    @Territory NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.Name AS Territory,
        COUNT(DISTINCT s.SalesOrderID) AS OrdersCount,
        SUM(s.SubTotal) AS TotalSales
    FROM Sales.SalesOrderHeader s
    INNER JOIN Sales.SalesTerritory t ON s.TerritoryID = t.TerritoryID
    WHERE t.Name = @Territory
    GROUP BY t.Name;
END;
GO
 
--test
EXEC Reporting.GetSalesByTerritory @Territory = 'Northwest';





--Task 3 ¡V Implement Secure Dynamic SQL
IF OBJECT_ID('Reporting.DynamicSalesReport', 'P') IS NOT NULL
    DROP TABLE Reporting.DynamicSalesReporty;
GO


CREATE OR ALTER PROCEDURE Reporting.DynamicSalesReport
    @Territory NVARCHAR(50) = NULL,
    @SalesPerson NVARCHAR(100) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT t.Name AS Territory,
               p.FirstName + '' '' + p.LastName AS SalesPerson,
               SUM(s.SubTotal) AS TotalSales
        FROM Sales.SalesOrderHeader s
        INNER JOIN Sales.SalesTerritory t ON s.TerritoryID = t.TerritoryID
        INNER JOIN Sales.SalesPerson sp ON s.SalesPersonID = sp.BusinessEntityID
        INNER JOIN Person.Person p ON sp.BusinessEntityID = p.BusinessEntityID
        WHERE 1=1';
 
    IF @Territory IS NOT NULL SET @SQL += N' AND t.Name = @Territory';
    IF @SalesPerson IS NOT NULL SET @SQL += N' AND (p.FirstName + '' '' + p.LastName) = @SalesPerson';
    IF @StartDate IS NOT NULL SET @SQL += N' AND s.OrderDate >= @StartDate';
    IF @EndDate IS NOT NULL SET @SQL += N' AND s.OrderDate <= @EndDate';
 
    SET @SQL += N' GROUP BY t.Name, p.FirstName, p.LastName ORDER BY TotalSales DESC';
 
    BEGIN TRY
        EXEC sp_executesql
            @SQL,
            N'@Territory NVARCHAR(50), @SalesPerson NVARCHAR(100), @StartDate DATE, @EndDate DATE',
            @Territory, @SalesPerson, @StartDate, @EndDate;
    END TRY
    BEGIN CATCH
        INSERT INTO Reporting.ExecutionLog (ProcedureName, ExecutedSQL, ErrorMessage)
        VALUES ('Reporting.DynamicSalesReport', @SQL, ERROR_MESSAGE());
    END CATCH;
END;
GO


--TESTS
EXEC Reporting.DynamicSalesReport @Territory = 'Northwest';
EXEC Reporting.DynamicSalesReport @SalesPerson = 'David Campbell';
EXEC Reporting.DynamicSalesReport @StartDate = '2022-01-01', @EndDate = '2022-12-31';
GO



--Task 4 ¡V Demonstrate SQL Injection Prevention
IF OBJECT_ID('Reporting VulnerableProductSearch', 'P') IS NOT NULL
DROP PROCEDURE Reporting. VulnerableProductSearch;
GO

CREATE OR ALTER PROCEDURE Reporting.VulnerableProductSearch
    @Category NVARCHAR(100)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT ProductID, Name FROM Production.Product
        WHERE Name LIKE ''%' + @Category + '%''';
    EXEC(@SQL);
END;
GO
 
CREATE OR ALTER PROCEDURE Reporting.SecureProductSearch
    @Category NVARCHAR(100)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT ProductID, Name FROM Production.Product
        WHERE Name LIKE @Pattern';
    DECLARE @Pattern NVARCHAR(102) = N'%' + @Category + N'%';
    EXEC sp_executesql @SQL, N'@Pattern NVARCHAR(102)', @Pattern;
END;
GO




--TESTS
EXEC Reporting.VulnerableProductSearch @Category = 'Road';
EXEC Reporting.SecureProductSearch @Category = 'Mountain' ;
GO



--Task 5 ¡V Implement Control-of-Flow and Output Parameters
IF OBJECT_ID('Reporting.CheckInventoryLevel', 'P') IS NOT NULL
DROP PROCEDURE Reporting.CheckInventoryLevel;
GO


CREATE OR ALTER PROCEDURE Reporting.CheckInventoryLevel
    @ProductID INT,
    @Status NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Qty INT;
    SELECT @Qty = SUM(Quantity) FROM Production.ProductInventory WHERE ProductID = @ProductID;
 
    IF @Qty IS NULL
        SET @Status = 'Unknown';
    ELSE IF @Qty < 50
        SET @Status = 'Low';
    ELSE
        SET @Status = 'Sufficient';
END;
GO
 
DECLARE @ProductStatus NVARCHAR(20);
EXEC Reporting.CheckInventoryLevel @ProductID = 776, @Status = @ProductStatus OUTPUT;
PRINT @ProductStatus;


--TEST
DECLARE @InventoryStatus NVARCHAR(20);
EXEC Reporting.CheckInventoryLevel @ProductID = 776, @Status = @InventoryStatus OUTPUT;
PRINT 'Inventory Status: ' + @InventoryStatus;
GO



--Task 6 ¡V Error Handling and Logging
IF OBJECT_ID('Reporting.SafeUpdateProductCost', 'P') IS NOT NULL
DROP PROCEDURE Reporting.SafeUpdateProductCost;
GO


CREATE OR ALTER PROCEDURE Reporting.SafeUpdateProductCost
    @ProductID INT,
    @NewListPrice MONEY
AS
BEGIN
    BEGIN TRAN;
    BEGIN TRY
        UPDATE Production.Product
        SET ListPrice = @NewListPrice
        WHERE ProductID = @ProductID;
 
        IF @@ROWCOUNT = 0
            THROW 51000, 'Product not found', 1;
 
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO Reporting.ExecutionLog (ProcedureName, ExecutedSQL, ErrorMessage)
        VALUES ('Reporting.SafeUpdateProductCost', 'UPDATE Production.Product...', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO


----TESTS
EXEC Reporting.SafeUpdateProductCost @ProductID = 680, @NewListPrice = 2100.00;-- valid
EXEC Reporting.SafeUpdateProductCost @ProductID = 999999, @NewListPrice = 2000.00;-- invalid to trigger log
GO

