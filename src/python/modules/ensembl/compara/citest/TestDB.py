# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Database framework for the Continuous Integration Test (CITest) suite.

This module defines the required classes to connect and test databases from different runs of the same
pipeline. The main class, TestDBItem, has been designed and implemented to be used with ``pytest``.

"""

from typing import Dict, List, Union

import pandas
import pytest
from _pytest._code.code import ExceptionChainRepr, ExceptionInfo, ReprExceptionInfo
from _pytest.fixtures import FixtureLookupErrorRepr
from sqlalchemy import text

from ensembl.compara.citest.CITest import CITestItem
from ensembl.compara.db.DBConnection import DBConnection


class TestDBItem(CITestItem):
    """Generic tests to compare a table in two (analogous) Ensembl Compara MySQL databases.

    Args:
        name: Name of the test to run.
        parent: The parent collector node.
        ref_db: Database connectivity and features of the reference database.
        target_db: Database connectivity and features of the target database.
        table: Table to be tested.
        args: Arguments to pass to the test call.

    Attributes:
        ref_db (DBConn): Database connectivity and features of the reference database.
        target_db (DBConn): Database connectivity and features of the target database.
        table (str): Table to be tested.

    """
    def __init__(self, name: str, parent: pytest.Item, ref_db: DBConnection, target_db: DBConnection,
                 table: str, args: Dict) -> None:
        super().__init__(name, parent, args)
        self.ref_db = ref_db
        self.target_db = target_db
        self.table = table

    def repr_failure(self, excinfo: ExceptionInfo, style: str = None
                    ) -> Union[str, ReprExceptionInfo, ExceptionChainRepr, FixtureLookupErrorRepr]:
        """Returns the failure representation that will be displayed in the report section.

        Note:
            This method is called when ``self.runtest()`` raises an exception.

        Args:
            excinfo: Exception information with additional support for navigating and traceback.
            style: Traceback print mode (``auto``/``long``/``short``/``line``/``native``/``no``).

        """
        if isinstance(excinfo.value, FailedDBTestException):
            self.error_info['expected'] = excinfo.value.args[0]
            self.error_info['found'] = excinfo.value.args[1]
            self.error_info['query'] = excinfo.value.args[2].strip()
            return excinfo.value.args[3] + "\n"
        return super().repr_failure(excinfo, style)

    def get_report_header(self) -> str:
        """Returns the header to display in the error report."""
        return "Database table: {}, test: {}".format(self.table, self.name)

    @staticmethod
    def _get_sql_filter(filter_by: Union[str, List, None]) -> str:
        """Returns an SQL WHERE clause including all the given conditions.

        If more than one condition is given, they will be joined by the AND operator and put inside
        parenthesis. Symbols that can be considered placeholders by sqlalchemy (like ``%``) will be doubled
        (``%%``) to keep their initial meaning.

        Args:
            filter_by: Condition(s) to be combined in the WHERE statement.

        Returns:
            An empty string if `filter_by` is empty, the SQL WHERE clause otherwise.

        """
        sql_filter = ""
        if filter_by:
            if isinstance(filter_by, list):
                filter_by = ") AND (".join(filter_by)
            # Single percentage symbols ("%") are interpreted as placeholders, so double them up
            filter_by = re.sub(r'(?<!%)%(?!%)', '%%', filter_by)
            sql_filter = "WHERE ({})".format(filter_by)
        return sql_filter

    def test_num_rows(self, variation: float = 0.0, group_by: Union[str, List] = None,
                      filter_by: Union[str, List] = None) -> None:
        """Compares the number of rows between reference and target tables.

        If `group_by` is provided, the number of rows will be compared per group, applying the same variation
        to all of them. If `filter_by` is provided, only the rows matching all the given conditions will be
        compared.

        Args:
            variation: Allowed variation between reference and target tables.
            group_by: Group rows by column(s), and count the number of rows per group.
            filter_by: Filter rows by one or more conditions (joined by the AND operator).

        Raise:
            FailedDBTestException: If `group_by` is provided and the number of groups is different; or if the
                number of rows differ for at least one group.

        """
        # Compose the sql query from the given parameters
        sql_filter = self._get_sql_filter(filter_by)
        if group_by:
            if isinstance(group_by, str):
                group_by = [group_by]
            # ORDER BY to ensure that the results are always in the same order (for the same groups)
            sql_query = "SELECT `{0}`, COUNT(*) as nrows FROM {1} {2} GROUP BY `{0}` ORDER BY `{0}`".format(
                "`,`".join(group_by), self.table, sql_filter)
        else:
            sql_query = "SELECT COUNT(*) as nrows FROM {} {}".format(self.table, sql_filter)
        # Get the number of rows for both databases
        ref_data = pandas.read_sql_query(sql_query, self.ref_db.bind)
        target_data = pandas.read_sql_query(sql_query, self.target_db.bind)
        # Check if the size of the returned tables are the same
        if ref_data.shape != target_data.shape:
            expected = ref_data.shape[0]
            found = target_data.shape[0]
            # Note: the shape can only be different if group_by is given
            message = "Different number of groups ({}) for table '{}'".format(", ".join(group_by), self.table)
            raise FailedDBTestException(expected, found, sql_query, message)
        # Check if the number of rows (per group) are the same
        difference = abs(ref_data['nrows'] - target_data['nrows'])
        allowed_variation = ref_data['nrows'] * variation
        failing_rows = difference > allowed_variation
        if failing_rows.any():
            expected_data = ref_data.loc[failing_rows]
            expected = [] if expected_data.empty else expected_data.to_string(index=False).splitlines()
            found_data = target_data.loc[failing_rows]
            found = [] if found_data.empty else found_data.to_string(index=False).splitlines()
            message = ("The difference in number of rows for table '{}' exceeds the allowed variation "
                       "({})").format(self.table, variation)
            raise FailedDBTestException(expected, found, sql_query, message)

    def test_content(self, columns: Union[str, List] = None, filter_by: Union[str, List] = None) -> None:
        """Compares the content between reference and target tables.

        The comparison is made only for the selected columns. The data and the data type of each column have
        to be the same in both tables in order to be considered equal.

        Args:
            columns: Columns to take into account in the comparison. If an empty string/list is provided, all
                columns will be included. Alternatively, it can be an exclusion list by adding ``-`` at the
                start of each column name, e.g. ``-job_id`` will make all columns but ``job_id`` to be
                included.
            filter_by: Filter rows by one or more conditions (joined by the AND operator).

        Raise:
            FailedDBTestException: If the number of rows differ; or if one or more rows have different
                content.

        """
        sql_filter = self._get_sql_filter(filter_by)
        if (columns is None) or isinstance(columns, str):
            columns = [columns] if columns else []
        if (not columns or all(col.startswith('-') for col in columns)):
            # Retrieve every column from the table and remove those in the exclusion list
            ref_columns = [col.name for col in self.ref_db.tables[self.table].columns]
            for col in columns:
                ref_columns.remove(col[1:])
            columns = ref_columns
        # Compose the sql query from the given parameters
        sql_query = "SELECT `{}` FROM {} {}".format("`,`".join(columns), self.table, sql_filter)
        # Get the table content for the selected columns
        ref_data = pandas.read_sql_query(sql_query, self.ref_db.bind)
        target_data = pandas.read_sql_query(sql_query, self.target_db.bind)
        # Check if the size of the returned tables are the same
        # Note: although not necessary, this control provides a better error message
        if ref_data.shape != target_data.shape:
            expected = ref_data.shape[0]
            found = target_data.shape[0]
            message = "Different number of rows in table '{}'".format(self.table)
            raise FailedDBTestException(expected, found, sql_query, message)
        # Compare the content of both dataframes, sorting them first to ensure they are comparable
        ref_data.sort_values(by=columns, inplace=True, kind='mergesort')
        target_data.sort_values(by=columns, inplace=True, kind='mergesort')
        failing_rows = ref_data.ne(target_data).any(axis='columns')
        if failing_rows.any():
            expected_data = ref_data.loc[failing_rows]
            expected = [] if expected_data.empty else expected_data.to_string(index=False).splitlines()
            found_data = target_data.loc[failing_rows]
            found = [] if found_data.empty else found_data.to_string(index=False).splitlines()
            message = "Table '{}' has different content for columns {}".format(self.table, ", ".join(columns))
            raise FailedDBTestException(expected, found, sql_query, message)


class FailedDBTestException(Exception):
    """Exception subclass created to handle test failures separatedly from unexpected exceptions."""
