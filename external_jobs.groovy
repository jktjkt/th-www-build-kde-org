import hudson.model.*

def view = Hudson.instance.getView("External_Deps")

if( view != null ) {
	for(item in view.getItems())
	{
		print("$item.name ")
	}
}