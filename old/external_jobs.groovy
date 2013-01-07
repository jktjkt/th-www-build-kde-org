import hudson.model.*

def view = Hudson.instance.getView("External_Deps")

if( view != null ) {
	for(item in view.getItems())
	{
		println("$item.name")
	}
} else {
	println("View not found")
}