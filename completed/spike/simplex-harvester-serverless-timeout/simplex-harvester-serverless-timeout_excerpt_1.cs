// Source: https://raw.githubusercontent.com/dotnet/efcore/main/src/EFCore.SqlServer/Storage/Internal/SqlServerTransientExceptionDetector.cs
// Fetched verbatim via `curl` on 2026-07-22 for SPIKE simplex-harvester-serverless-timeout.
// This is the default transient-error check used by EF Core's SqlServerRetryingExecutionStrategy
// (the strategy activated by `sqlOptions.EnableRetryOnFailure()` with no arguments, as used in
// simplex-harvester's Helpers/UtilHelper.cs:14 and :21).
//
// Only the tail of the switch statement is reproduced here — the part that matters for this
// investigation: the numeric error codes near the end of the case list, the fallthrough to
// `return true`, and — the key finding — error -2 (SQL command/connection timeout), which is
// explicitly commented OUT of the case list with a rationale comment.
//
// Full file: 709 lines. Case labels 49983 down to 233 (lines 30-673 in the original) all fall
// through, with no code between them, to the single `return true;` shown below. That includes
// case 40613 (line 184 in the original — "Database XXXX on server YYYY is not currently
// available... retry the connection later" — the classic Azure SQL serverless auto-resume error).

                    // SQL Error Code: 233
                    // The client was unable to establish a connection because of an error during connection initialization process before login.
                    // Possible causes include the following: the client tried to connect to an unsupported version of SQL Server;
                    // the server was too busy to accept new connections; or there was a resource limitation (insufficient memory or maximum
                    // allowed connections) on the server. (provider: TCP Provider, error: 0 - An existing connection was forcibly closed by
                    // the remote host.)
                    case 233:
                        return true;
                    // SQL Error Code: 203
                    // A connection was successfully established with the server, but then an error occurred during the pre-login handshake.
                    // (provider: TCP Provider, error: 0 - 20) ---> System.ComponentModel.Win32Exception (203): Unknown error: 203
                    case 203:
                        if (ex.InnerException is Win32Exception)
                        {
                            return true;
                        }

                        continue;
                    // SQL Error Code: 121
                    // The semaphore timeout period has expired
                    case 121:
                    // SQL Error Code: 64
                    // A connection was successfully established with the server, but then an error occurred during the login process.
                    // (provider: TCP Provider, error: 0 - The specified network name is no longer available.)
                    case 64:
                    // DBNETLIB Error Code: 20
                    // The instance of SQL Server you attempted to connect to does not support encryption.
                    case 20:
                        return true;
                    // This exception can be thrown even if the operation completed successfully, so it's safer to let the application fail.
                    // DBNETLIB Error Code: -2
                    // Timeout expired. The timeout period elapsed prior to completion of the operation or the server is not responding. The statement has been terminated.
                    //case -2:
                }
            }

            return false;
        }

        return ex is TimeoutException;
    }
}
