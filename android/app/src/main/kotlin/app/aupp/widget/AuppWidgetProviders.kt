package app.aupp.widget

class AuppOverviewWidgetProvider : AuppWidgetProvider() {
    override val kind = Kind.OVERVIEW
    override val keyPrefix = "aupp_overview"
}

class AuppIncomeWidgetProvider : AuppWidgetProvider() {
    override val kind = Kind.SINGLE
    override val keyPrefix = "aupp_income"
}

class AuppExpensesWidgetProvider : AuppWidgetProvider() {
    override val kind = Kind.SINGLE
    override val keyPrefix = "aupp_expenses"
}

class AuppBalanceWidgetProvider : AuppWidgetProvider() {
    override val kind = Kind.SINGLE
    override val keyPrefix = "aupp_balance"
}
